# frozen_string_literal: true

class Favourite < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation
  include ObjectCounterManagement

  belongs_to :actor, class_name: 'Actor'
  belongs_to :object, class_name: 'ActivityPubObject'

  validates :actor_id, uniqueness: { scope: :object_id }

  scope :recent, -> { order(created_at: :desc) }

  tracks_object_counter :favourites_count
  after_create :create_notification_for_favourite
end
