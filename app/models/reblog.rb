# frozen_string_literal: true

class Reblog < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  before_validation :set_ap_id, on: :create
  after_create :increment_reblogs_count
  after_create :create_notification
  after_create :send_push_notification
  after_destroy :decrement_reblogs_count

  private

  def increment_reblogs_count
    object.increment!(:reblogs_count)
  end

  def decrement_reblogs_count
    object.decrement!(:reblogs_count)
  end

  def create_notification
    create_notification_for_reblog
  end

  def send_push_notification
    WebPushDelivery.deliver_reblog_notification(self)
  end
end
