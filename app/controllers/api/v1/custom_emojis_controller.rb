# frozen_string_literal: true

module Api
  module V1
    class CustomEmojisController < Api::BaseController
      # Mastodon API準拠 - カスタム絵文字一覧取得
      # GET /api/v1/custom_emojis
      def index
        render json: Rails.cache.fetch('api:v1:custom_emojis', expires_in: 1.hour) {
          CustomEmoji.enabled.alphabetical.includes(:image_attachment).map(&:to_activitypub)
        }
      end
    end
  end
end
