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
                         .order(id: :desc)
                         .then { |n| apply_notification_pagination(n) }
                         .limit(notification_limit_param)
                         .to_a

        # Linkヘッダーを設定（マーカー注入前に行い、ページネーションを壊さない）
        add_notification_pagination_headers(@notifications, :api_v1_notifications_url)

        # マーカー通知がリストに含まれることを保証（Moshidon互換）
        inject_marker_notification_if_missing!

        # ActivityPubObjectsを一括取得してN+1を回避
        activity_pub_objects = preload_activity_pub_objects(@notifications)
        preload_all_status_data(activity_pub_objects.values) if activity_pub_objects.any?

        # 通知送信者のアカウント絵文字・最終投稿日もプリロード
        from_accounts = @notifications.filter_map(&:from_account).uniq(&:id)
        preload_account_emojis(from_accounts)
        preload_last_status_at(from_accounts.map(&:id))

        render json: @notifications.map { |notification|
          notification_json_with_preloaded(notification, activity_pub_objects)
        }
      end

      # GET /api/v1/notifications/:id
      def show
        activity_pub_objects = preload_activity_pub_objects([@notification])
        preload_all_status_data(activity_pub_objects.values) if activity_pub_objects.any?
        render json: notification_json_with_preloaded(@notification, activity_pub_objects)
      end

      # POST /api/v1/notifications/clear
      def clear
        current_user.notifications.delete_all
        # マーカーも削除して整合性を保つ
        current_user.markers.for_timeline('notifications').destroy_all
        head :ok
      end

      # POST /api/v1/notifications/:id/dismiss
      def dismiss
        update_marker_if_needed(@notification)
        @notification.destroy!
        head :ok
      end

      private

      def set_notification
        @notification = current_user.notifications.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Notification')
      end

      # マーカー通知がレスポンスに含まれない場合、ソート位置に挿入する
      # Moshidonはマーカーと完全一致するIDをリスト内で探すため、
      # 欠落するとページサイズ(40)が未読数として表示される
      def inject_marker_notification_if_missing!
        return if @notifications.empty?

        marker = current_user.markers.for_timeline('notifications').first
        return unless marker&.last_read_id

        marker_id = marker.last_read_id
        return if @notifications.any? { |n| n.id.to_s == marker_id }

        # マーカーIDがリスト範囲内（最新と最古の間）の場合のみ注入
        newest_id = @notifications.first.id
        oldest_id = @notifications.last.id
        marker_id_int = marker_id.to_i
        return unless marker_id_int < newest_id && marker_id_int >= oldest_id

        marker_notification = current_user.notifications
                                          .includes(:from_account)
                                          .find_by(id: marker_id)
        return unless marker_notification

        # id降順のソート位置に挿入（末尾追加ではなく正しい位置に挿入）
        insert_index = @notifications.index { |n| n.id < marker_id_int } || @notifications.size
        @notifications.insert(insert_index, marker_notification)
      end

      # 削除対象の通知がマーカーの場合、直前の通知にマーカーを移動
      def update_marker_if_needed(notification)
        marker = current_user.markers.for_timeline('notifications').first
        return unless marker&.last_read_id == notification.id.to_s

        older = current_user.notifications
                            .where(id: ...notification.id)
                            .order(id: :desc)
                            .first
        if older
          marker.update!(last_read_id: older.id.to_s)
        else
          marker.destroy
        end
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
        exclude_types = params[:exclude_types] || params[:excludeTypes]
        return notifications if exclude_types.blank?

        notifications.where.not(notification_type: exclude_types)
      end

      def filter_by_account(notifications)
        account_id = params[:account_id] || params[:accountId]
        return notifications if account_id.blank?

        notifications.where(from_account_id: account_id)
      end

      def notification_json_with_preloaded(notification, activity_pub_objects)
        status = if status_notification?(notification) && notification.activity_type == 'ActivityPubObject'
                   activity_pub_objects[notification.activity_id]
                 end

        {
          id: notification.id.to_s,
          type: notification.notification_type,
          created_at: notification.created_at.iso8601,
          account: serialized_account(notification.from_account),
          status: status ? serialized_status(status) : nil
        }
      end
    end
  end
end
