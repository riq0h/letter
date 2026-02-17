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
end
