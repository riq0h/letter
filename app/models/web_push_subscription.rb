# frozen_string_literal: true

class WebPushSubscription < ApplicationRecord
  include PushPayloadBuilder

  belongs_to :actor

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true

  scope :active, -> { where.not(endpoint: nil).where('created_at > ?', subscription_expiry_threshold) }
  scope :expired, -> { where(created_at: ..subscription_expiry_threshold) }

  def data_hash
    JSON.parse(data || '{}')
  rescue JSON::ParserError
    {}
  end

  def data_hash=(hash)
    self.data = hash.to_json
  end

  def alerts
    data_hash['alerts'] || default_alerts
  end

  def alerts=(alert_hash)
    current_data = data_hash
    current_data['alerts'] = alert_hash
    self.data_hash = current_data
  end

  def default_alerts
    {
      'follow' => true,
      'follow_request' => true,
      'favourite' => true,
      'reblog' => true,
      'mention' => true,
      'poll' => true,
      'status' => false,
      'update' => false,
      'quote' => true,
      'admin.sign_up' => false,
      'admin.report' => false
    }
  end

  def push_payload(notification_type, title, body, options = {})
    build_push_payload(notification_type, title, body, options)
  end

  def should_send_alert?(notification_type)
    alerts[notification_type.to_s] == true
  end

  def policy
    data_hash['policy'] || 'all'
  end

  def policy=(new_policy)
    valid_policies = %w[all followed follower none]
    policy_value = valid_policies.include?(new_policy.to_s) ? new_policy.to_s : 'all'

    current_data = data_hash
    current_data['policy'] = policy_value
    self.data_hash = current_data
  end

  def should_receive_notification_from?(from_actor, target_actor, notification_type)
    # アラート設定をまずチェック
    return false unless should_send_alert?(notification_type)

    # ポリシーに基づいて判定
    case policy
    when 'none'
      false
    when 'followed'
      # 通知を受ける人がフォローしている相手からのみ
      Follow.exists?(actor: target_actor, target_actor: from_actor, accepted: true)
    when 'follower'
      # フォロワーからのみ
      Follow.exists?(actor: from_actor, target_actor: target_actor, accepted: true)
    else
      true # デフォルトは 'all' または未知の値の場合
    end
  end

  def expired?
    created_at <= self.class.subscription_expiry_threshold
  end

  def expires_at
    created_at + self.class.subscription_expiry_duration
  end

  def days_until_expiry
    return 0 if expired?

    ((expires_at - Time.current) / 1.day).ceil
  end

  class << self
    def subscription_expiry_duration
      365.days
    end

    def subscription_expiry_threshold
      subscription_expiry_duration.ago
    end

    def cleanup_expired_subscriptions!
      expired_count = expired.count
      if expired_count.positive?
        Rails.logger.info "🧹 Cleaning up #{expired_count} expired WebPush subscriptions"
        expired.delete_all
      end
      expired_count
    end
  end

  private

  def default_icon
    "#{Rails.application.config.activitypub.base_url}/favicon.ico"
  end

  def default_badge
    "#{Rails.application.config.activitypub.base_url}/favicon.ico"
  end
end
