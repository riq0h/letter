# frozen_string_literal: true

require 'blurhash'

module Api
  module V2
    class MediaController < Api::BaseController
      include MediaSerializer
      include MediaAttachmentSerialization
      include MediaAttachmentCreation

      before_action :doorkeeper_authorize!, :require_user!

      # POST /api/v2/media
      def create
        media_attachment = create_media_attachment(media_params[:file], processing_status: 'completed')

        render json: serialized_media_attachment(media_attachment), status: :ok
      rescue StandardError => e
        Rails.logger.error "Media creation error: #{e.message}"
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def media_params
        params.permit(:file, :description)
      end

      # メディアメタデータ構築メソッドは MediaSerializer から継承
    end
  end
end
