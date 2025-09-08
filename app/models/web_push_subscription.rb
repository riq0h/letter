# frozen_string_literal: true

class WebPushSubscription < ApplicationRecord
  include PushPayloadBuilder

  belongs_to :actor

  validates :endpoint, presence: true, uniqueness: { scope: :actor_id }
  validates :p256dh_key, presence: true
  validates :auth_key, presence: true

  scope :active, -> { where.not(endpoint: nil) }

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

  private

  def default_icon
    "#{Rails.application.config.activitypub.base_url}/favicon.ico"
  end

  def default_badge
    "#{Rails.application.config.activitypub.base_url}/favicon.ico"
  end
end
