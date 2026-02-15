# frozen_string_literal: true

module Api
  module V2
    class InstanceController < Api::BaseController
      include VapidKeyHelper
      include AccountSerializer
      # GET /api/v2/instance
      def show
        render json: instance_v2_serializer
      end

      private

      def instance_v2_serializer
        {
          domain: Rails.application.config.activitypub.domain,
          title: load_instance_setting('instance_name') || 'letter',
          version: '0.1',
          source_url: 'https://github.com/riq0h/letter',
          description: load_instance_setting('instance_description') || 'General Letter Publication System based on ActivityPub',
          usage: usage_stats,
          thumbnail: {
            url: '',
            blurhash: nil,
            versions: {}
          },
          languages: %w[ja en],
          configuration: configuration_data,
          registrations: {
            enabled: false,
            approval_required: false,
            message: nil
          },
          contact: contact_info,
          rules: []
        }
      end

      def usage_stats
        {
          users: {
            active_month: Actor.where(local: true).count
          }
        }
      end

      def configuration_data
        {
          urls: {
            streaming: "wss://#{Rails.application.config.activitypub.domain}/api/v1/streaming"
          },
          vapid: {
            public_key: vapid_public_key || 'not_configured'
          },
          accounts: {
            max_featured_tags: 10
          },
          statuses: {
            max_characters: Rails.application.config.activitypub.character_limit,
            max_media_attachments: 4,
            characters_reserved_per_url: 23
          },
          media_attachments: {
            supported_mime_types: MediaAttachmentCreationService::ALLOWED_MIME_TYPES,
            image_size_limit: MediaAttachment::MAX_IMAGE_SIZE,
            image_matrix_limit: 16_777_216,
            video_size_limit: MediaAttachment::MAX_VIDEO_SIZE,
            video_frame_rate_limit: 60,
            video_matrix_limit: 2_304_000
          },
          polls: {
            max_options: 4,
            max_characters_per_option: 50,
            min_expiration: 300,
            max_expiration: 2_629_746
          }
        }
      end

      def contact_info
        admin_actor = Actor.where(local: true, admin: true).first
        return { email: load_instance_setting('contact_email') || '' } unless admin_actor

        {
          email: load_instance_setting('contact_email') || '',
          account: serialized_account(admin_actor)
        }
      end

      def load_instance_setting(key)
        case key
        when 'instance_name'
          InstanceConfig.get('instance_name')
        when 'instance_description'
          InstanceConfig.get('instance_description')
        when 'instance_contact_email', 'contact_email'
          InstanceConfig.get('instance_contact_email')
        end
      end
    end
  end
end
