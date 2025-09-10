# frozen_string_literal: true

require 'blurhash'

module Api
  module V1
    class MediaController < Api::BaseController
      include MediaSerializer
      include MediaAttachmentSerialization
      include MediaAttachmentCreation

      before_action :doorkeeper_authorize!

      # GET /api/v1/media/:id
      def show
        media_attachment = current_user.media_attachments.find(params[:id])
        render json: serialized_media_attachment(media_attachment)
      rescue ActiveRecord::RecordNotFound
        render_not_found('Media')
      end

      # POST /api/v1/media
      def create
        return render_authentication_required unless current_user

        file = params[:file]
        return render_missing_parameter('File') unless file

        begin
          media_attachment = create_media_attachment(file)
          render json: serialized_media_attachment(media_attachment), status: :created
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error "Media upload validation failed: #{e.message}"
          render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
        rescue StandardError => e
          Rails.logger.error "Media upload failed: #{e.message}"
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/media/:id
      def update
        media_attachment = current_user.media_attachments.find(params[:id])

        if media_attachment.update(media_update_params)
          render json: serialized_media_attachment(media_attachment)
        else
          render json: {
            error: 'Validation failed',
            details: media_attachment.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render_not_found('Media')
      end

      private

      def media_update_params
        params.permit(:description)
      end

      # メディアメタデータ構築メソッドは MediaSerializer から継承
    end
  end
end
