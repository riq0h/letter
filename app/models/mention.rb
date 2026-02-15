# frozen_string_literal: true

class Mention < ApplicationRecord
  include ApIdGeneration
  include NotificationCreation

  belongs_to :object, class_name: 'ActivityPubObject'
  belongs_to :actor

  validates :ap_id, presence: true, uniqueness: true

  after_create :create_notification_for_mention

  scope :local, -> { joins(:actor).where(actors: { local: true }) }
  scope :remote, -> { joins(:actor).where(actors: { local: false }) }

  # Mastodon API互換のacct形式を返す
  def acct
    if actor.local?
      actor.username
    else
      "#{actor.username}@#{actor.domain}"
    end
  end
end
