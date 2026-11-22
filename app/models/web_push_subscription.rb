# frozen_string_literal: true

class WebPushSubscription < ApplicationRecord
  include PushPayloadBuilder

  belongs_to :actor
  belongs_to :access_token, class_name: 'Doorkeeper::AccessToken', optional: true

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true

  # 送信先が通知を保持する時間(TTLヘッダ)
  PUSH_TTL = 48.hours

  # 送信先(中継サーバなど)が「もう届かない」と判断したときに購読を消せるよう、送信ごとに解除用URLを付ける。
  # 送信先が届けるのを諦めた後でも呼べるよう、有効期間はTTLの倍にする
  generates_token_for :unsubscribe, expires_in: PUSH_TTL * 2

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
    stored = data_hash['alerts']
    return default_alerts unless stored.is_a?(Hash)

    stored.transform_values { |value| self.class.alert_enabled?(value) }
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

  # ログアウトなどでトークンが無効になった購読には送らない(クライアントはそのトークンで通知を取りに来られない)
  def token_usable?
    access_token.present? && access_token.accessible?
  end

  def unsubscribe_url
    path = Rails.application.routes.url_helpers.web_push_unsubscribe_path(generate_token_for(:unsubscribe))
    "#{Rails.application.config.activitypub.base_url}#{path}"
  end

  def expires_at
    created_at + self.class.subscription_expiry_duration
  end

  def days_until_expiry
    return 0 if expired?

    ((expires_at - Time.current) / 1.day).ceil
  end

  class << self
    # 通知設定は文字列("true"/"false")で送ってくるクライアントもあるので、真偽値として読む
    def alert_enabled?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def subscription_expiry_duration
      3650.days
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
end
