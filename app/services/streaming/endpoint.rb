# frozen_string_literal: true

require 'websocket/driver'

module Streaming
  # GET /api/v1/streaming。Mastodonのストリーミングと同じく、WebSocketで接続して購読したストリームの
  # 出来事を受け取る。トークンはAuthorizationヘッダ・access_token・Sec-WebSocket-Protocolのどれでもよい
  class Endpoint
    READ_SCOPES = %w[read read:statuses read:notifications read:lists].freeze

    def self.call(env)
      new(env).call
    end

    def initialize(env)
      @env = env
    end

    def call
      token = access_token
      user = token && Actor.find_by(id: token.resource_owner_id, local: true)
      return error(401, 'Error: Invalid access token') unless user

      scopes = token.scopes.to_a
      return error(401, 'Access token does not have the required scopes') unless READ_SCOPES.intersect?(scopes)
      return error(400, 'Only WebSocket connections are supported') unless WebSocket::Driver.websocket?(@env)
      return error(500, 'This server cannot take over the connection') unless @env['rack.hijack']
      return error(503, 'Too many connections') if Hub.instance.full?

      Connection.new(@env, user: user, scopes: scopes, protocol: protocol_token).start
      [-1, {}, []]
    end

    private

    def access_token
      value = bearer_token || Rack::Request.new(@env).params['access_token'].presence || protocol_token
      return unless value

      token = Doorkeeper::AccessToken.find_by(token: value)
      token if token && !token.expired? && !token.revoked?
    end

    def bearer_token
      @env['HTTP_AUTHORIZATION'].to_s[/\ABearer\s+(.+)\z/i, 1]
    end

    # ブラウザのWebSocketはヘッダを付けられないので、トークンをSec-WebSocket-Protocolで送る
    # (masto.jsなど)。そのときは同じ値を応答で返さないと、ブラウザが接続を切る
    def protocol_token
      @env['HTTP_SEC_WEBSOCKET_PROTOCOL'].to_s.split(',').first.to_s.strip.presence
    end

    def error(status, message)
      [status, { 'content-type' => 'application/json' }, [{ error: message }.to_json]]
    end
  end
end
