# frozen_string_literal: true

require 'websocket/driver'

module Streaming
  # WebSocketの接続1本。Pumaから接続を引き取り(rack.hijack)、読み書きを自分のスレッドで行うので、
  # 接続している間もPumaのスレッドをふさがない
  class Connection
    # 途中のCloudflareは100秒やり取りが無い接続を切る
    PING_INTERVAL = 30
    # この間クライアントから何も届かなければ(pingへの応答も無ければ)切れたとみなす
    IDLE_TIMEOUT = 75
    READ_SIZE = 16 * 1024

    # websocket-driverが使う
    attr_reader :env, :url

    def initialize(env, user:, scopes:, protocol:, hub: Hub.instance)
      @env = env
      @url = "wss://#{env['HTTP_HOST']}#{env['PATH_INFO']}"
      @user = user
      @protocol = protocol
      @hub = hub
      @outbox = Thread::Queue.new
      @monitor = Monitor.new
      @closed = false
      @session = Session.new(user: user, scopes: scopes, transport: self, on_change: -> { hub.subscriptions_changed })
    end

    def start
      @io = env['rack.hijack'].call
      @driver = WebSocket::Driver.rack(self, protocols: [@protocol].compact)
      @driver.on(:open) { opened }
      @driver.on(:message) { |event| @session.receive(event.data) }
      @driver.on(:close) { close }
      @last_seen = @last_ping = monotonic
      @monitor.synchronize { @driver.start }
      Thread.new { read_loop }.name = 'streaming-read'
      Thread.new { write_loop }.name = 'streaming-write'
    end

    # websocket-driverが送信に使う
    delegate :write, to: :@io

    # Sessionが送信に使う
    def send_text(text)
      @outbox << text unless @closed
    end

    def close
      @monitor.synchronize do
        return if @closed

        @closed = true
      end
      @hub.unregister(@session)
      @outbox << :close
      begin
        @monitor.synchronize { @driver.close }
        @io.close
      rescue StandardError
        nil
      end
      Rails.logger.info "📡 Streaming disconnected: user #{@user.id}"
    end

    private

    def opened
      @hub.register(@session)
      @session.open(Rack::Request.new(env).params)
      Rails.logger.info "📡 Streaming connected: user #{@user.id} (#{@hub.sessions.size} in this process)"
    end

    def read_loop
      until @closed
        data = @io.readpartial(READ_SIZE)
        @last_seen = monotonic
        Rails.application.executor.wrap { @monitor.synchronize { @driver.parse(data) } }
      end
    rescue IOError, SystemCallError
      nil
    rescue StandardError => e
      Rails.logger.error "📡 Streaming read error: #{e.class}: #{e.message}"
    ensure
      close
    end

    def write_loop
      until @closed
        message = @outbox.pop(timeout: [PING_INTERVAL - (monotonic - @last_ping), 0.1].max)
        break if message == :close

        @monitor.synchronize { @driver.text(message) } if message
        next if monotonic - @last_ping < PING_INTERVAL
        break if monotonic - @last_seen > IDLE_TIMEOUT

        @monitor.synchronize { @driver.ping }
        @last_ping = monotonic
      end
    rescue IOError, SystemCallError
      nil
    rescue StandardError => e
      Rails.logger.error "📡 Streaming write error: #{e.class}: #{e.message}"
    ensure
      close
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
