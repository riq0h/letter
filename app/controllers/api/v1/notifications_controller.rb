# frozen_string_literal: true

module Api
  module V1
    class NotificationsController < Api::BaseController
      include StatusSerializationHelper
      include NotificationHelper

      before_action :doorkeeper_authorize!, only: %i[index show clear dismiss]
      before_action :require_user!, only: %i[index show clear dismiss]
      before_action :set_notification, only: %i[show dismiss]

      # GET /api/v1/notifications
      def index
        @notifications = filtered_notifications
                         .recent
                         .then { |n| apply_notification_pagination(n) }
                         .limit(notification_limit_param)

        # ActivityPubObjectsを一括取得してN+1を回避
        activity_pub_objects = preload_activity_pub_objects(@notifications)

        # Linkヘッダーを設定（Mastodon互換）
        add_notification_pagination_headers(@notifications, :api_v1_notifications_url)

        render json: @notifications.map { |notification|
          notification_json_with_preloaded(notification, activity_pub_objects)
        }
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

      def notification_json_with_preloaded(notification, activity_pub_objects)
        json = notification_json(notification)

        # ActivityPubObjectの場合は事前読み込みデータを使用
        if notification.activity_type == 'ActivityPubObject' && activity_pub_objects[notification.activity_id]
          preloaded_activity = activity_pub_objects[notification.activity_id]
          json[:status] = serialized_status(preloaded_activity) if status_notification?(notification)
        end

        json
      end

      def notification_json(notification)
        {
          id: notification.id.to_s,
          type: notification.notification_type,
          created_at: notification.created_at.iso8601,
          account: serialized_account(notification.from_account),
          status: status_json_if_present(notification)
        }
      end

      def status_json_if_present(notification)
        return nil unless status_notification?(notification)

        status = notification.activity
        return nil unless status.is_a?(ActivityPubObject)

        serialized_status(status)
      end
    end
  end
end
