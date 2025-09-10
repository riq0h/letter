# frozen_string_literal: true

class Marker < ApplicationRecord
  belongs_to :actor

  validates :timeline, presence: true, inclusion: { in: %w[home notifications] }
  validates :last_read_id, presence: true
  validates :actor_id, uniqueness: { scope: :timeline }

  scope :for_timeline, ->(timeline) { where(timeline: timeline) }
  scope :recent, -> { order(updated_at: :desc) }

  def self.find_or_initialize_for_actor_and_timeline(actor, timeline)
    find_or_initialize_by(actor: actor, timeline: timeline)
  end

  def increment_version!
    self.version = (version || 0) + 1
    touch if persisted?
  end
end
