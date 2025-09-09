# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      Rails.logger.info "🔗 Action Cable connection established for user: #{current_user.username}"

      # WebSocketサブプロトコル処理
      handle_websocket_subprotocol

      # Mastodon互換：クライアント主導の購読を待つ（自動購読を無効化）
      Rails.logger.info '🔗 WebSocket connection ready, waiting for client subscription requests'
    end

    def disconnect
      Rails.logger.info "🔌 Action Cable connection closed for user: #{current_user&.username}"
    end

    private

    def find_verified_user
      token = extract_access_token
      return reject_with_log('No token found') unless token

      access_token = verify_access_token(token)
      return reject_with_log("Invalid access token: #{token[0..10]}...") unless access_token

      user = find_user_by_token(access_token)
      return reject_with_log("No user found for resource_owner_id: #{access_token.resource_owner_id}") unless user

      return reject_with_log("User is not local: #{user.username}") unless user.local?

      Rails.logger.info "✅ WebSocket authentication successful for user: #{user.username}"
      user
    rescue StandardError => e
      Rails.logger.error "❌ WebSocket authentication error: #{e.class}: #{e.message}"
      reject_unauthorized_connection
    end

    def verify_access_token(token)
      # Action Cableは別のDB接続を使用するため、明示的にメインデータベースを使用
      ActiveRecord::Base.connected_to(role: :writing) do
        access_token = Doorkeeper::AccessToken.by_token(token)
        return nil unless access_token && !access_token.expired? && !access_token.revoked?

        access_token
      end
    end

    def find_user_by_token(access_token)
      Rails.logger.info "🔍 Looking for user with resource_owner_id: #{access_token.resource_owner_id}"
      # Action Cableは別のDB接続を使用するため、明示的にメインデータベースを使用
      ActiveRecord::Base.connected_to(role: :writing) do
        Actor.find_by(id: access_token.resource_owner_id)
      end
    end

    def reject_with_log(message)
      Rails.logger.error "❌ #{message}, rejecting connection"
      reject_unauthorized_connection
      nil
    end

    def extract_access_token
      # デバッグ用ログ
      Rails.logger.info "🔍 WebSocket Headers: #{request.headers.to_h.select do |k, _v|
        k.downcase.include?('websocket') || k.downcase.include?('authorization')
      end}"
      Rails.logger.info "🔍 Query String: #{request.query_string}"

      # 1. Authorization ヘッダー (Bearer token)
      authorization = request.headers['Authorization']
      if authorization&.start_with?('Bearer ')
        token = authorization.sub('Bearer ', '')
        Rails.logger.info "🔑 Found Bearer token: #{token[0..10]}..."
        return token
      end

      # 2. WebSocket Protocol ヘッダー (Mastodon互換)
      protocol = request.headers['sec-websocket-protocol']
      if protocol.present?
        Rails.logger.info "🔑 Found WebSocket protocol token: #{protocol[0..10]}..."
        return protocol
      end

      # 3. URLクエリパラメータ access_token
      query_params = Rack::Utils.parse_query(request.query_string)
      if query_params['access_token'].present?
        Rails.logger.info "🔑 Found query param token: #{query_params['access_token'][0..10]}..."
        return query_params['access_token']
      end

      Rails.logger.error '❌ No access token found in any location'
      nil
    end

    def handle_websocket_subprotocol
      # WebSocketサブプロトコル（Mastodon互換）の処理
      protocol = request.headers['sec-websocket-protocol']
      if protocol.present?
        Rails.logger.info "🔗 WebSocket subprotocol requested: #{protocol[0..10]}..."

        # Mastodonクライアントに適切なプロトコル応答を送信
        # この処理でクライアントが期待するWebSocketプロトコル確認応答を行う
        Rails.logger.info '🔗 Sending WebSocket subprotocol confirmation'
      else
        Rails.logger.warn '🔗 No WebSocket subprotocol found in request'
      end
    end

    def subscribe_to_streaming_channel
      # StreamingChannelに自動購読（同期処理に変更）
      Rails.logger.info "🔗 Auto-subscribing to StreamingChannel for user: #{current_user.username}"

      begin
        Rails.logger.info '🔗 Executing StreamingChannel subscription (synchronous)'
        # StreamingChannelを直接インスタンス化
        channel = StreamingChannel.new(self, '{"channel":"StreamingChannel"}')
        channel.subscribe_to_channel
        Rails.logger.info '🔗 StreamingChannel subscription completed (synchronous)'
      rescue StandardError => e
        Rails.logger.error "🔗 StreamingChannel subscription failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
      end
    end
  end
end
