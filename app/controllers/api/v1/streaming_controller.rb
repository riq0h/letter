# frozen_string_literal: true

module Api
  module V1
    class StreamingController < Api::BaseController
      before_action :doorkeeper_authorize!
      before_action :set_cors_headers

      # GET /api/v1/streaming
      def index
        render json: {
          endpoint: websocket_url,
          connection_params: {
            access_token: doorkeeper_token.token
          },
          usage: {
            url: "#{websocket_url}?stream=user&access_token=#{doorkeeper_token.token}",
            available_streams: %w[user public public:local hashtag hashtag:local list direct]
          }
        }
      end

      private

      def websocket_url
        # WebSocketエンドポイントのURLを生成
        protocol = request.ssl? ? 'wss' : 'ws'
        domain = Rails.application.config.activitypub.domain || request.host
        port = request.ssl? ? '' : ":#{request.port}"

        "#{protocol}://#{domain}#{port}/api/v1/streaming"
      end

      def set_cors_headers
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
      end
    end
  end
end
