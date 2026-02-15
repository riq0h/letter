# frozen_string_literal: true

class Reblog < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation
  include ObjectCounterManagement

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  tracks_object_counter :reblogs_count
  after_create :create_notification_for_reblog
  after_commit :send_push_notification, on: :create

  private

  def send_push_notification
    WebPushDelivery.deliver_reblog_notification(self)
  rescue StandardError => e
    Rails.logger.error "Failed to send reblog push notification: #{e.message}"
  end
end
