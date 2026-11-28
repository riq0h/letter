# frozen_string_literal: true

module Streaming
  # Pumaの1プロセスが持つストリーミングの接続の取りまとめ。記録された出来事(StreamingEvent)を
  # 読み取って各接続に配る。接続がある間だけ動く
  class Hub
    POLL_INTERVAL = 0.5
    # Listeners::TTLより十分短くする
    MARK_INTERVAL = 20
    TRIM_INTERVAL = 60
    BATCH_SIZE = 200
    MAX_SESSIONS = 50

    @instance_lock = Mutex.new

    class << self
      def instance
        @instance_lock.synchronize do
          @instance = nil if @instance_pid != Process.pid
          @instance_pid = Process.pid
          @instance ||= new
        end
      end

      def reset!
        @instance_lock.synchronize do
          @instance&.stop
          @instance = nil
        end
      end
    end

    def initialize
      @sessions = []
      @lock = Mutex.new
      @dispatch_lock = Mutex.new
      @last_id = 0
      @last_run = {}
      @stopped = false
    end

    def full?
      @lock.synchronize { @sessions.size >= MAX_SESSIONS }
    end

    def sessions
      @lock.synchronize { @sessions.dup }
    end

    def register(session)
      # 接続が無かった間の出来事は配らない
      latest_id = StreamingEvent.maximum(:id).to_i
      @lock.synchronize do
        @last_id = latest_id if @sessions.empty?
        @sessions << session
      end
      mark_listeners
      ensure_thread
    end

    def unregister(session)
      @lock.synchronize { @sessions.delete(session) }
    end

    # 購読が増えたら、出来事の記録を待たせないよう、すぐに目印を付け直す
    def subscriptions_changed
      mark_listeners
    end

    # まだ配っていない出来事を読み、各接続に配る
    def dispatch_pending
      @dispatch_lock.synchronize do
        current = sessions
        return if current.empty?

        events = StreamingEvent.after(@lock.synchronize { @last_id }).limit(BATCH_SIZE).to_a
        return if events.empty?

        @lock.synchronize { @last_id = events.last.id }
        deliver(events, current)
      end
    end

    def stop
      @stopped = true
    end

    private

    def deliver(events, current)
      renderers = {}
      events.each do |event|
        current.each do |session|
          renderer = renderers[session.user.id] ||= Renderer.new(session.user)
          session.deliver(event, renderer)
        rescue StandardError => e
          Rails.logger.error "📡 Failed to deliver streaming event #{event.kind} #{event.target_id}: #{e.class}: #{e.message}"
        end
      end
    end

    def mark_listeners
      current = sessions
      Listeners.mark(user_ids: current.map { |s| s.user.id }.uniq, timelines: current.any?(&:timelines?))
    end

    def ensure_thread
      @lock.synchronize do
        return if @thread&.alive?

        @thread = Thread.new { run }
        @thread.name = 'streaming-hub'
      end
    end

    def run
      until @stopped
        sleep POLL_INTERVAL
        next if sessions.empty?

        tick
      end
    end

    def tick
      Rails.application.executor.wrap do
        dispatch_pending
        mark_listeners if due?(:mark, MARK_INTERVAL)
        StreamingEvent.trim if due?(:trim, TRIM_INTERVAL)
      end
    rescue StandardError => e
      Rails.logger.error "📡 Streaming hub error: #{e.class}: #{e.message}"
    end

    def due?(name, interval)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return false if @last_run[name] && now - @last_run[name] < interval

      @last_run[name] = now
    end
  end
end
