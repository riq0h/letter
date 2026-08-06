# frozen_string_literal: true

module Api
  module V2
    class InstanceController < Api::BaseController
      include VapidKeyHelper
      include AccountSerializer

      # GET /api/v2/instance
      def show
        render json: Rails.cache.fetch('api:v2:instance', expires_in: 5.minutes) { instance_v2_serializer }
      end

      private

      def instance_v2_serializer
        {
          domain: Rails.application.config.activitypub.domain,
          title: load_instance_setting('instance_name') || 'letter',
          # v1と同じくクライアントの機能判定に使われる(4.5互換を名乗る)
          version: '4.5.0 (compatible; letter 0.1)',
          source_url: 'https://github.com/riq0h/letter',
          description: load_instance_setting('instance_description') || 'General Letter Publication System based on ActivityPub',
          usage: usage_stats,
          thumbnail: {
            url: instance_icon_url,
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
          rules: [],
          api_versions: {
            # Mastodon 4.5系が名乗る値(公式docsの実例と同じ)。クライアントの新しい機能判定手段
            mastodon: 6
          }
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
            streaming: "https://#{Rails.application.config.activitypub.domain}/api/v1/streaming"
          },
          vapid: {
            public_key: vapid_public_key || 'not_configured'
          },
          accounts: {
            max_featured_tags: 10,
            # Mastodon 4.6互換: プロフィール編集UIの文字数上限表示に使われる
            max_note_length: 500,
            max_display_name_length: 30
          },
          statuses: {
            max_characters: Rails.application.config.activitypub.character_limit,
            max_media_attachments: 16,
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

      def instance_icon_url
        base_url = "#{Rails.application.config.activitypub.protocol}://#{Rails.application.config.activitypub.domain}"
        icon_path = Rails.public_path.join('instance.png')
        File.exist?(icon_path) ? "#{base_url}/instance.png" : ''
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
