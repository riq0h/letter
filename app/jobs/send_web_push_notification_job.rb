# frozen_string_literal: true

class SendWebPushNotificationJob < ApplicationJob
  queue_as :default

  def perform(subscription_id, notification_type, title, body, options = {})
    subscription = WebPushSubscription.find_by(id: subscription_id)
    return unless subscription

    WebPushDelivery.deliver_to_subscription(
      subscription,
      notification_type,
      title,
      body,
      options.symbolize_keys
    )
  end
end
