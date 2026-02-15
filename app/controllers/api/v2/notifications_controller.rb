# frozen_string_literal: true

module Api
  module V2
    class NotificationsController < Api::BaseController
      include StatusSerializationHelper
      include NotificationHelper

      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v2/notifications
      # Mastodon 4.3+ grouped notifications
      def index
        notifications = filtered_notifications
                        .recent
                        .then { |n| apply_notification_pagination(n) }
                        .limit(notification_limit_param)

        # ActivityPubObjectsを一括取得してN+1を回避
        activity_pub_objects = preload_activity_pub_objects(notifications)

        # グループ化
        groups = build_notification_groups(notifications, activity_pub_objects)

        # Linkヘッダーを設定
        add_notification_pagination_headers(notifications, :api_v2_notifications_url)

        render json: {
          accounts: groups[:accounts].values,
          statuses: groups[:statuses].values,
          notification_groups: groups[:groups]
        }
      end

      # GET /api/v2/notifications/unread_count
      def unread_count
        count = current_user.notifications.unread.count
        render json: { count: count }
      end

      private

      def filtered_notifications
        base = current_user.notifications.includes(:from_account)
        base = base.where(notification_type: params[:types]) if params[:types].present?
        base = base.where.not(notification_type: params[:exclude_types]) if params[:exclude_types].present?
        base
      end

      def build_notification_groups(notifications, activity_pub_objects)
        accounts = {}
        statuses = {}
        groups = []
        group_map = {}

        notifications.each do |notification|
          from_account = notification.from_account
          accounts[from_account.id.to_s] = serialized_account(from_account) unless accounts.key?(from_account.id.to_s)

          status = resolve_notification_status(notification, activity_pub_objects)
          statuses[status.id.to_s] = serialized_status(status) if status && !statuses.key?(status.id.to_s)

          group_key = build_group_key(notification, status)
          accumulate_group({ map: group_map, list: groups }, group_key, notification, from_account, status)
        end

        { accounts: accounts, statuses: statuses, groups: groups }
      end

      def resolve_notification_status(notification, activity_pub_objects)
        return unless notification.activity_type == 'ActivityPubObject' && status_notification?(notification)

        activity_pub_objects[notification.activity_id]
      end

      def accumulate_group(result, group_key, notification, from_account, status)
        if result[:map].key?(group_key)
          update_existing_group(result[:map][group_key], notification, from_account)
        else
          group = create_new_group(group_key, notification, from_account, status)
          result[:map][group_key] = group
          result[:list] << group
        end
      end

      def update_existing_group(group, notification, from_account)
        account_id = from_account.id.to_s
        group[:sample_account_ids] << account_id unless group[:sample_account_ids].include?(account_id)
        group[:notifications_count] += 1
        group[:page_max_id] = notification.id.to_s if notification.id.to_s > group[:page_max_id]
        group[:latest_page_notification_at] = notification.created_at.iso8601
      end

      def create_new_group(group_key, notification, from_account, status)
        {
          group_key: group_key,
          notifications_count: 1,
          type: notification.notification_type,
          most_recent_notification_id: notification.id.to_s,
          page_min_id: notification.id.to_s,
          page_max_id: notification.id.to_s,
          latest_page_notification_at: notification.created_at.iso8601,
          sample_account_ids: [from_account.id.to_s],
          status_id: status&.id&.to_s
        }
      end

      def build_group_key(notification, status)
        if status
          "#{notification.notification_type}-#{status.id}"
        else
          "#{notification.notification_type}-#{notification.from_account_id}-#{notification.id}"
        end
      end
    end
  end
end
