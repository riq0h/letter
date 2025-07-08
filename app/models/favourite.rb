# frozen_string_literal: true

class Favourite < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  scope :recent, -> { order(created_at: :desc) }

  before_validation :set_ap_id, on: :create
  after_create :increment_favourites_count
  after_create :create_notification
  after_create :send_push_notification
  after_destroy :decrement_favourites_count

  private

  def increment_favourites_count
    object.increment!(:favourites_count)
  end

  def decrement_favourites_count
    object.decrement!(:favourites_count)
  end

  def create_notification
    create_notification_for_favourite
  end

  def send_push_notification
    WebPushDelivery.deliver_favourite_notification(self)
  end
end
