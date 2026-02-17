# frozen_string_literal: true

module Api
  module V1
    class InstanceController < Api::BaseController
      include VapidKeyHelper

      # GET /api/v1/instance/peers
      def peers
        domains = Actor.where(local: false)
                       .where.not(domain: nil)
                       .distinct
                       .pluck(:domain)
                       .compact
        render json: domains
      end

      # GET /api/v1/instance/activity
      def activity
        weeks = (0..11).map do |i|
          week_start = i.weeks.ago.beginning_of_week
          week_end = i.weeks.ago.end_of_week

          statuses = ActivityPubObject.where(object_type: 'Note', created_at: week_start..week_end).count
          logins = Actor.where(local: true).count # 簡易的にローカルユーザー数を返す
          registrations = 0

          {
            week: week_start.to_i.to_s,
            statuses: statuses.to_s,
            logins: logins.to_s,
            registrations: registrations.to_s
          }
        end

        render json: weeks
      end

      # GET /api/v1/instance/rules
      def rules
        render json: []
      end

      # GET /api/v1/instance (DEPRECATED - use v2/instance instead)
      def show
        # 非推奨警告をレスポンスヘッダに追加
        response.headers['Deprecation'] = 'true'
        response.headers['Sunset'] = 'Tue, 31 Dec 2024 23:59:59 GMT'
        response.headers['Link'] = '</api/v2/instance>; rel="successor-version"'

        render json: instance_info
      end

      private

      def instance_info
        local_domain = Rails.application.config.activitypub.domain

        # ログでドメイン設定を確認
        Rails.logger.info "Instance API v1: domain=#{local_domain}"

        {
          domain: local_domain,
          uri: local_domain,
          title: InstanceConfig.get('instance_name') || 'letter',
          short_description: InstanceConfig.get('instance_description') || 'General Letter Publication System based on ActivityPub',
          description: InstanceConfig.get('instance_description') || 'General Letter Publication System based on ActivityPub',
          email: InstanceConfig.get('instance_contact_email') || Rails.application.config.instance_contact_email || '',
          version: '0.1.0 (compatible; letter 0.1.0)',
          urls: {
            streaming_api: "https://#{local_domain}/api/v1/streaming"
          },
          stats: {
            user_count: Actor.where(local: true).count,
            status_count: ActivityPubObject.where(object_type: 'Note').count,
            domain_count: Actor.where(local: false).distinct.count(:domain)
          },
          languages: %w[ja en],
          registrations: false,
          approval_required: false,
          invites_enabled: false,
          configuration: {
            urls: {
              streaming: "https://#{local_domain}/api/v1/streaming"
            },
            accounts: {
              max_featured_tags: 0
            },
            statuses: {
              max_characters: Rails.application.config.activitypub.character_limit,
              max_media_attachments: 4,
              characters_reserved_per_url: 23
            },
            media_attachments: {
              supported_mime_types: [
                'image/jpeg',
                'image/png',
                'image/gif',
                'image/webp',
                'video/mp4',
                'video/webm'
              ],
              image_size_limit: 52_428_800, # 50MB
              image_matrix_limit: 16_777_216,
              video_size_limit: 524_288_000, # 500MB
              video_frame_rate_limit: 60,
              video_matrix_limit: 2_304_000
            },
            polls: {
              max_options: 4,
              max_characters_per_option: 50,
              min_expiration: 300,
              max_expiration: 2_629_746
            }
          },
          vapid_public_key: vapid_public_key,
          contact_account: nil,
          rules: []
        }
      end
    end
  end
end
