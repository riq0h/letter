# frozen_string_literal: true

module PushPayloadBuilder
  extend ActiveSupport::Concern

  def build_push_payload(notification_type, title, body, options = {})
    {
      access_token: access_token&.token,
      preferred_locale: 'ja',
      notification_id: options[:notification_id],
      notification_type: notification_type,
      icon: options[:icon] || '/icon.png',
      title: title,
      body: body
    }
  end
end
