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
      return reject_unauthorized_connection unless token

      # Doorkeeper のアクセストークンを検証
      access_token = Doorkeeper::AccessToken.by_token(token)
      return reject_unauthorized_connection unless access_token&.acceptable?

      # ユーザを取得
      user = Actor.find_by(id: access_token.resource_owner_id)
      return reject_unauthorized_connection unless user&.local?

      user
    rescue StandardError
      reject_unauthorized_connection
    end

    def extract_access_token
      # 1. Authorization ヘッダー (Bearer token)
      authorization = request.headers['Authorization']
      return authorization.sub('Bearer ', '') if authorization&.start_with?('Bearer ')

      # 2. WebSocket Protocol ヘッダー (Mastodon互換)
      protocol = request.headers['sec-websocket-protocol']
      return protocol if protocol.present?

      # 3. URLクエリパラメータ access_token
      query_params = Rack::Utils.parse_query(request.query_string)
      query_params['access_token']
    end
  end
end
