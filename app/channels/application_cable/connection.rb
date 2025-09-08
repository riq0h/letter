# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # Mastodon互換のOAuth トークン取得
      token = extract_access_token
      unless token
        Rails.logger.error '❌ No token found, rejecting connection'
        return reject_unauthorized_connection
      end

      # Doorkeeper のアクセストークンを検証
      access_token = Doorkeeper::AccessToken.by_token(token)
      unless access_token
        Rails.logger.error "❌ Invalid access token: #{token[0..10]}..."
        return reject_unauthorized_connection
      end

      unless access_token.acceptable?
        Rails.logger.error "❌ Access token not acceptable (expired/revoked): #{token[0..10]}..."
        return reject_unauthorized_connection
      end

      # ユーザを取得
      user = Actor.find_by(id: access_token.resource_owner_id)
      unless user
        Rails.logger.error "❌ No user found for resource_owner_id: #{access_token.resource_owner_id}"
        return reject_unauthorized_connection
      end

      unless user.local?
        Rails.logger.error "❌ User is not local: #{user.username}"
        return reject_unauthorized_connection
      end

      Rails.logger.info "✅ WebSocket authentication successful for user: #{user.username}"
      user
    rescue StandardError => e
      Rails.logger.error "❌ WebSocket authentication error: #{e.class}: #{e.message}"
      reject_unauthorized_connection
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
  end
end
