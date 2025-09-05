# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < Api::BaseController
      include StatusSerializer
      include StatusSerializationHelper
      include MediaSerializer
      include PollSerializer
      include MentionTagSerializer

      before_action :doorkeeper_authorize!, only: %i[index show clear dismiss]
      before_action :require_user!, only: %i[index show clear dismiss]
      before_action :set_notification, only: %i[show dismiss]

      # GET /api/v1/notifications
      def index
        @notifications = filtered_notifications
                         .recent
                         .then { |n| apply_pagination(n) }
                         .limit(limit_param)

        render json: @notifications.map { |notification| notification_json(notification) }
      end

      # GET /api/v1/notifications/:id
      def show
        render json: notification_json(@notification)
      end

      # POST /api/v1/notifications/clear
      def clear
        current_user.notifications.delete_all
        head :ok
      end

      # POST /api/v1/notifications/:id/dismiss
      def dismiss
        @notification.destroy!
        head :ok
      end

      private

      def set_notification
        @notification = current_user.notifications.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Notification')
      end

      def filtered_notifications
        base_notifications
          .then { |n| filter_by_types(n) }
          .then { |n| filter_by_excluded_types(n) }
          .then { |n| filter_by_account(n) }
      end

      def base_notifications
        current_user.notifications.includes(:from_account)
      end

      def filter_by_types(notifications)
        return notifications if params[:types].blank?

        notifications.where(notification_type: params[:types])
      end

      def filter_by_excluded_types(notifications)
        return notifications if params[:exclude_types].blank?

        notifications.where.not(notification_type: params[:exclude_types])
      end

      def filter_by_account(notifications)
        return notifications if params[:account_id].blank?

        notifications.where(from_account_id: params[:account_id])
      end

      def limit_param
        [params.fetch(:limit, 40).to_i, 80].min
      end

      def notification_json(notification)
        {
          id: notification.id.to_s,
          type: notification.notification_type,
          created_at: notification.created_at.iso8601,
          account: account_json(notification.from_account),
          status: status_json_if_present(notification)
        }
      end

      def account_json(actor)
        basic_account_info(actor).merge(
          account_media_info(actor)
        ).merge(
          account_count_info(actor)
        ).merge(
          account_metadata
        )
      end

      def basic_account_info(actor)
        {
          id: actor.id.to_s,
          username: actor.username,
          acct: actor.local? ? actor.username : "#{actor.username}@#{actor.domain}",
          display_name: actor.display_name || actor.username,
          locked: false,
          bot: false,
          discoverable: true,
          group: false,
          created_at: actor.created_at.iso8601,
          note: actor.note || '',
          url: actor.ap_id
        }
      end

      def account_media_info(actor)
        {
          avatar: actor.avatar_url || '/avatars/missing.png',
          avatar_static: actor.avatar_url || '/avatars/missing.png',
          header: actor.header_url || '/headers/missing.png',
          header_static: actor.header_url || '/headers/missing.png'
        }
      end

      def account_count_info(actor)
        {
          followers_count: actor.followers_count || 0,
          following_count: actor.following_count || 0,
          statuses_count: actor.objects.where(object_type: 'Note').count,
          last_status_at: actor.objects.where(object_type: 'Note').maximum(:published_at)&.iso8601
        }
      end

      def account_metadata
        {
          emojis: [],
          fields: []
        }
      end

      def status_json_if_present(notification)
        return nil unless status_notification?(notification)

        status = extract_status(notification)
        return nil unless status

        build_status_json(status)
      end

      def extract_status(notification)
        status = notification.activity
        status.is_a?(ActivityPubObject) ? status : nil
      end

      def status_notification?(notification)
        %w[mention reblog favourite status update poll quote].include?(notification.notification_type)
      end

      def build_status_json(status)
        basic_status_info(status).merge(
          status_counts(status)
        ).merge(
          status_metadata(status)
        )
      end

      def basic_status_info(status)
        {
          id: status.id,
          created_at: status.published_at&.iso8601 || status.created_at.iso8601,
          in_reply_to_id: nil,
          in_reply_to_account_id: nil,
          sensitive: status.sensitive?,
          spoiler_text: status.summary || '',
          visibility: status.visibility,
          language: status.language,
          uri: status.ap_id,
          url: status.url || status.ap_id,
          content: parse_content_links_only(status.content || ''),
          account: account_json(status.actor)
        }
      end

      def status_counts(status)
        {
          replies_count: status.replies_count || 0,
          reblogs_count: status.reblogs_count || 0,
          favourites_count: status.favourites_count || 0
        }
      end

      def status_metadata(status)
        {
          reblog: nil,
          media_attachments: serialized_media_attachments(status),
          mentions: serialized_mentions(status),
          tags: serialized_tags(status),
          emojis: serialized_emojis(status),
          card: nil,
          poll: serialize_poll(status)
        }
      end

      def apply_pagination(notifications)
        notifications = notifications.where(notifications: { id: ...(params[:max_id]) }) if params[:max_id].present?

        notifications = notifications.where('notifications.id > ?', params[:since_id]) if params[:since_id].present?

        notifications = notifications.where('notifications.id > ?', params[:min_id]) if params[:min_id].present?

        notifications
      end
    end
  end
end
