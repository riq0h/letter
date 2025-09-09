# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
      Rails.logger.info "Action Cable connection established for user: #{current_user.username}"
      handle_websocket_subprotocol
      Rails.logger.info 'WebSocket connection ready, waiting for client subscription requests'
    end

    def disconnect
      Rails.logger.info "Action Cable connection closed for user: #{current_user&.username}"
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
      authorization = request.headers['Authorization']
      return authorization.sub('Bearer ', '') if authorization&.start_with?('Bearer ')

      protocol = request.headers['sec-websocket-protocol']
      return protocol if protocol.present?

      query_params = Rack::Utils.parse_query(request.query_string)
      return query_params['access_token'] if query_params['access_token'].present?

      Rails.logger.error '❌ No access token found'
      nil
    end

    def handle_websocket_subprotocol
      protocol = request.headers['sec-websocket-protocol']
      if protocol.present?
        Rails.logger.info '🔗 WebSocket subprotocol requested'
      else
        Rails.logger.warn '🔗 No WebSocket subprotocol found'
      end
    end

    def subscribe_to_streaming_channel
      channel = StreamingChannel.new(self, '{"channel":"StreamingChannel"}')
      channel.subscribe_to_channel
      Rails.logger.info '🔗 StreamingChannel subscription completed'
    rescue StandardError => e
      Rails.logger.error "🔗 StreamingChannel subscription failed: #{e.message}"
    end
  end
end
