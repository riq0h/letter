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

        # デバッグ: 通知の中身を確認
        notifications.first(3).each do |n|
          Rails.logger.info "DEBUG notif id=#{n.id} type=#{n.notification_type} activity_type=#{n.activity_type.inspect} activity_id=#{n.activity_id.inspect}"
        end
        Rails.logger.info "DEBUG activity_pub_objects keys=#{activity_pub_objects.keys.first(5).inspect} (#{activity_pub_objects.count} total)"

        # グループ化
        groups = build_notification_groups(notifications, activity_pub_objects)

        # Linkヘッダーを設定
        add_notification_pagination_headers(notifications, :api_v2_notifications_url)

        response_data = {
          accounts: groups[:accounts].values,
          statuses: groups[:statuses].values,
          notification_groups: groups[:groups]
        }

        Rails.logger.info "V2 Notifications: #{groups[:statuses].count} statuses, #{groups[:groups].count} groups"
        groups[:groups].each do |g|
          Rails.logger.info "  group: type=#{g[:type]} status_id=#{g[:status_id].inspect}"
        end

        render json: response_data
      end

      # GET /api/v2/notifications/:group_key
      def show
        notifications = current_user.notifications.recent

        # ActivityPubObjectsを一括取得
        activity_pub_objects = preload_activity_pub_objects(notifications)

        # group_keyに一致するグループを検索
        target_group = nil
        notifications.each do |notification|
          status = resolve_notification_status(notification, activity_pub_objects)
          group_key = build_group_key(notification, status)
          next unless group_key == params[:group_key]

          if target_group.nil?
            target_group = create_new_group(group_key, notification, notification.from_account, status)
          else
            update_existing_group(target_group, notification, notification.from_account)
          end
        end

        if target_group
          render json: target_group
        else
          render json: { error: 'Record not found' }, status: :not_found
        end
      end

      # POST /api/v2/notifications/:group_key/dismiss
      def dismiss
        notifications = current_user.notifications
        target_ids = find_notification_ids_for_group(notifications, params[:group_key])

        notifications.where(id: target_ids).destroy_all if target_ids.any?

        head :ok
      end

      # POST /api/v2/notifications/clear
      def clear
        current_user.notifications.delete_all
        head :ok
      end

      # GET /api/v2/notifications/unread_count
      def unread_count
        marker = current_user.markers.for_timeline('notifications').first

        # Mastodon互換: マーカーが未設定の場合は0を返す
        unless marker
          render json: { count: 0 }
          return
        end

        scope = current_user.notifications.where('id > ?', marker.last_read_id.to_i)
        scope = scope.where(notification_type: params[:types]) if params[:types].present?
        scope = scope.where.not(notification_type: params[:exclude_types]) if params[:exclude_types].present?
        scope = scope.where(from_account_id: params[:account_id]) if params[:account_id].present?

        limit = (params[:limit] || 1000).to_i.clamp(1, 1000)
        render json: { count: [scope.count, limit].min }
      end

      private

      def filtered_notifications
        exclude_types = params[:exclude_types] || params[:excludeTypes]

        base = current_user.notifications.includes(:from_account)
        base = base.where(notification_type: params[:types]) if params[:types].present?
        base = base.where.not(notification_type: exclude_types) if exclude_types.present?
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
        group[:page_max_id] = notification.id.to_s if notification.id > group[:page_max_id].to_i
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

      def find_notification_ids_for_group(notifications, group_key)
        activity_pub_objects = preload_activity_pub_objects(notifications)

        notifications.filter_map do |notification|
          status = resolve_notification_status(notification, activity_pub_objects)
          key = build_group_key(notification, status)
          notification.id if key == group_key
        end
      end
    end
  end
end
