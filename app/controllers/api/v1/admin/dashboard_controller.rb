# frozen_string_literal: true

module Api
  module V1
    module Admin
      class DashboardController < Api::BaseController
        include AdminAuthorization

        before_action :doorkeeper_authorize!
        before_action :require_admin!

        # GET /api/v1/admin/dashboard
        def show
          render json: {
            software: 'letter',
            version: '0.1',
            stats: {
              user_count: Actor.local.count,
              status_count: ActivityPubObject.where(local: true, object_type: 'Note').count,
              domain_count: Actor.remote.distinct.count(:domain),
              last_week_users: Actor.local.where('created_at > ?', 1.week.ago).count
            },
            trends: [],
            last_backup_at: nil,
            config: {
              statuses_config: {
                max_characters: Rails.application.config.activitypub.character_limit,
                max_media_attachments: 4,
                characters_reserved_per_url: 23
              },
              media_attachments: {
                supported_mime_types: MediaAttachmentCreationService::ALLOWED_MIME_TYPES,
                image_size_limit: MediaAttachment::MAX_IMAGE_SIZE,
                video_size_limit: MediaAttachment::MAX_VIDEO_SIZE
              },
              accounts: {
                max_featured_tags: 10
              }
            }
          }
        end
      end
    end
  end
end
