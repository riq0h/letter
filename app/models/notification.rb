# frozen_string_literal: true

class Notification < ApplicationRecord
  # アソシエーション
  belongs_to :account, class_name: 'Actor', inverse_of: :notifications
  belongs_to :from_account, class_name: 'Actor', inverse_of: :sent_notifications

  # ポリモーフィック関連（activity_type + activity_id）
  def activity
    return nil unless activity_type && activity_id

    case activity_type
    when 'Follow'
      Follow.find_by(id: activity_id)
    when 'ActivityPubObject'
      ActivityPubObject.find_by(id: activity_id)
    end
  end

  # 通知タイプの定義
  TYPES = %w[
    mention
    status
    reblog
    follow
    follow_request
    favourite
    poll
    update
    quote
    admin.sign_up
    admin.report
  ].freeze

  # バリデーション
  validates :notification_type, inclusion: { in: TYPES }
  validates :activity_type, presence: true
  validates :activity_id, presence: true

  # コールバック
  after_create :send_push_notification
  after_create :deliver_to_streaming

  # スコープ
  scope :unread, -> { where(read: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_account, ->(account) { where(account: account) }
  scope :of_type, ->(type) { where(notification_type: type) }

  # 既読にする
  def mark_as_read!
    update!(read: true)
  end

  # 通知作成のクラスメソッド
  def self.create_follow_notification(follow)
    create!(
      account: follow.target_actor,
      from_account: follow.actor,
      activity_type: 'Follow',
      activity_id: follow.id.to_s,
      notification_type: 'follow'
    )
  end

  def self.create_follow_request_notification(follow)
    create!(
      account: follow.target_actor,
      from_account: follow.actor,
      activity_type: 'Follow',
      activity_id: follow.id.to_s,
      notification_type: 'follow_request'
    )
  end

  def self.create_mention_notification(mention, status)
    create!(
      account: mention.actor,
      from_account: status.actor,
      activity_type: 'ActivityPubObject',
      activity_id: status.id.to_s,
      notification_type: 'mention'
    )
  end

  def self.create_favourite_notification(favourite, status)
    create!(
      account: status.actor,
      from_account: favourite.actor,
      activity_type: 'ActivityPubObject',
      activity_id: status.id.to_s,
      notification_type: 'favourite'
    )
  end

  def self.create_reblog_notification(reblog, original_status)
    create!(
      account: original_status.actor,
      from_account: reblog.actor,
      activity_type: 'ActivityPubObject',
      activity_id: original_status.id.to_s,
      notification_type: 'reblog'
    )
  end

  def self.create_quote_notification(quote_post, quoted_status)
    create!(
      account: quoted_status.actor,
      from_account: quote_post.actor,
      activity_type: 'ActivityPubObject',
      activity_id: quote_post.object.id.to_s,
      notification_type: 'quote'
    )
  end

  private

  def send_push_notification
    case notification_type
    when 'follow', 'follow_request'
      send_follow_notification
    when 'mention', 'status', 'update', 'poll'
      send_status_notification
    when 'favourite', 'reblog', 'quote'
      send_interaction_notification
    end
  rescue StandardError => e
    Rails.logger.error "Failed to send push notification: #{e.message}"
  end

  def send_follow_notification
    if notification_type == 'follow'
      WebPushDelivery.deliver_follow_notification(from_account, account, id)
    else
      WebPushDelivery.deliver_follow_request_notification(from_account, account, id)
    end
  end

  def send_status_notification
    status = activity
    return unless status

    case notification_type
    when 'mention'
      WebPushDelivery.deliver_mention_notification(status, account, id)
    when 'poll'
      WebPushDelivery.deliver_poll_notification(status, account, id)
    when 'status'
      WebPushDelivery.deliver_status_notification(status, account, id)
    when 'update'
      WebPushDelivery.deliver_update_notification(status, account, id)
    end
  end

  def send_interaction_notification
    status = activity
    return unless status

    case notification_type
    when 'favourite'
      favourite = Favourite.find_by(actor: from_account, object: status)
      WebPushDelivery.deliver_favourite_notification(favourite, id) if favourite
    when 'reblog'
      reblog = Reblog.find_by(actor: from_account, object: status)
      WebPushDelivery.deliver_reblog_notification(reblog, id) if reblog
    when 'quote'
      quote_post = QuotePost.find_by(object: status)
      WebPushDelivery.deliver_quote_notification(quote_post, id) if quote_post
    end
  end

  def deliver_to_streaming
    serialized_notification = serialize_for_streaming

    # 即座にユーザに通知配信
    SseConnectionManager.instance.broadcast_to_user(account_id, 'notification', serialized_notification)

    Rails.logger.info "📡 Notification #{id} (#{notification_type}) delivered to user #{account_id}"
  rescue StandardError => e
    Rails.logger.error "💥 Notification streaming delivery error: #{e.message}"
  end

  def serialize_for_streaming
    {
      id: id.to_s,
      type: notification_type,
      created_at: created_at.iso8601,
      account: serialize_account(from_account),
      status: activity.is_a?(ActivityPubObject) ? serialize_activity_object : nil
    }
  end

  def serialize_account(actor)
    {
      id: actor.id.to_s,
      username: actor.username,
      acct: actor.acct,
      display_name: actor.display_name || actor.username,
      avatar: actor.avatar_url || '',
      url: actor.public_url || actor.ap_id
    }
  end

  def serialize_activity_object
    return nil unless activity.is_a?(ActivityPubObject)

    status = activity
    {
      id: status.id.to_s,
      content: status.content || '',
      created_at: status.published_at&.iso8601,
      account: serialize_account(status.actor),
      visibility: status.visibility
    }
  end
end
