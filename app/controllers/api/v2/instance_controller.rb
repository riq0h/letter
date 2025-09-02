# frozen_string_literal: true

module Api
  module V2
    class InstanceController < Api::BaseController
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
            streaming: "wss://#{Rails.application.config.activitypub.domain}"
          },
          vapid: {
            public_key: ENV['VAPID_PUBLIC_KEY'] || 'not_configured'
          },
          accounts: {
            max_featured_tags: 10
          },
          statuses: {
            max_characters: 500,
            max_media_attachments: 4,
            characters_reserved_per_url: 23
          },
          media_attachments: {
            supported_mime_types: [
              'image/jpeg',
              'image/png',
              'image/gif',
              'image/heic',
              'image/heif',
              'image/webp',
              'image/avif',
              'video/webm',
              'video/mp4',
              'video/quicktime',
              'video/ogg',
              'audio/wave',
              'audio/wav',
              'audio/x-wav',
              'audio/x-pn-wave',
              'audio/ogg',
              'audio/vorbis',
              'audio/mpeg',
              'audio/mp3',
              'audio/webm',
              'audio/flac',
              'audio/aac',
              'audio/m4a',
              'audio/x-m4a',
              'audio/mp4',
              'audio/3gpp',
              'video/x-ms-asf'
            ],
            image_size_limit: 10_485_760,
            image_matrix_limit: 16_777_216,
            video_size_limit: 41_943_040,
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
          account: serialize_contact_account(admin_actor)
        }
      end

      def serialize_contact_account(actor)
        {
          id: actor.id.to_s,
          username: actor.username,
          acct: actor.username,
          display_name: actor.display_name || actor.username,
          locked: false,
          bot: false,
          discoverable: true,
          group: false,
          created_at: actor.created_at.iso8601,
          note: actor.note || '',
          url: actor.public_url || actor.ap_id || '',
          avatar: actor.avatar_url || '',
          avatar_static: actor.avatar_url || '',
          header: actor.header_url || '',
          header_static: actor.header_url || '',
          followers_count: 0,
          following_count: 0,
          statuses_count: actor.posts_count || 0,
          emojis: [],
          fields: []
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
