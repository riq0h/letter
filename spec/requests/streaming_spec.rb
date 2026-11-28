# frozen_string_literal: true

require 'rails_helper'
require 'socket'
require 'websocket/driver'

RSpec.describe 'Streaming API', type: :request do
  let!(:user) { create(:actor) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Client', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application, scopes: 'read write')
  end

  after { Streaming::Hub.reset! }

  it 'answers the health check' do
    get '/api/v1/streaming/health'

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('OK')
  end

  it 'requires a token' do
    get '/api/v1/streaming'

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to include('error')
  end

  it 'accepts only WebSocket connections' do
    get '/api/v1/streaming', headers: { 'Authorization' => "Bearer #{access_token.token}" }

    expect(response).to have_http_status(:bad_request)
  end

  it 'tells clients to connect with WebSocket to this server' do
    get '/api/v2/instance'

    expect(response.parsed_body.dig('configuration', 'urls', 'streaming')).to eq('wss://test.example.com')
  end

  describe 'a WebSocket connection' do
    # ブラウザのWebSocketと同じく、トークンをSec-WebSocket-Protocolで送るクライアント(masto.jsと同じ)
    let(:client_class) do
      Class.new do
        attr_reader :driver, :received, :io

        def initialize(token)
          @token = token
          @received = []
          @opened = false
        end

        # 接続を始め、サーバに渡すリクエスト(env)を返す
        def handshake_env
          server_io, @io = UNIXSocket.pair
          buffer = StringIO.new
          socket = Struct.new(:url, :io) { delegate :write, to: :io }
                         .new('wss://test.example.com/api/v1/streaming', buffer)
          @driver = WebSocket::Driver.client(socket, protocols: [@token])
          @driver.on(:open) { @opened = true }
          @driver.on(:message) { |event| @received << JSON.parse(event.data) }
          @driver.start
          socket.io = @io

          Rack::MockRequest.env_for('/api/v1/streaming',
                                    'HTTP_HOST' => 'test.example.com', 'HTTP_UPGRADE' => 'websocket',
                                    'HTTP_CONNECTION' => 'Upgrade',
                                    'HTTP_SEC_WEBSOCKET_KEY' => buffer.string[/Sec-WebSocket-Key: (\S+)/, 1],
                                    'HTTP_SEC_WEBSOCKET_VERSION' => '13', 'HTTP_SEC_WEBSOCKET_PROTOCOL' => @token,
                                    'rack.hijack' => -> { server_io })
        end

        def opened?
          @opened
        end

        # 条件を満たすまでサーバからの通信を読む
        def read_until(timeout: 5)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          until yield
            raise 'timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            next unless @io.wait_readable(0.1)

            @driver.parse(@io.read_nonblock(16_384))
          end
        end
      end
    end
    let(:client) { client_class.new(access_token.token) }

    before { allow(Streaming::Listeners).to receive_messages(listening?: true, timelines_listening?: true) }

    after { client.io&.close }

    def wait_until(timeout: 5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    end

    def connect
      status, = Streaming::Endpoint.call(client.handshake_env)
      client.read_until { client.opened? }
      status
    end

    it 'completes the handshake, echoing the token sent as the protocol' do
      expect(connect).to eq(-1)
      expect(client.driver.protocol).to eq(access_token.token)
    end

    it 'delivers a notification to the subscribed stream' do
      connect
      client.driver.text({ type: 'subscribe', stream: 'user:notification' }.to_json)
      wait_until { Streaming::Hub.instance.sessions.first&.subscriptions&.any? }

      status = create(:activity_pub_object, :remote, actor: create(:actor, :remote))
      notification = create(:notification, account: user, activity_id: status.id.to_s)
      Streaming::Hub.instance.dispatch_pending
      client.read_until { client.received.any? }

      expect(client.received.first).to include('stream' => %w[user:notification], 'event' => 'notification')
      expect(JSON.parse(client.received.first['payload'])).to include('id' => notification.id.to_s)
    end

    it 'forgets the connection once the client goes away' do
      connect
      expect(Streaming::Hub.instance.sessions.size).to eq(1)

      client.io.close
      wait_until { Streaming::Hub.instance.sessions.empty? }

      expect(Streaming::Hub.instance.sessions).to be_empty
    end
  end
end
