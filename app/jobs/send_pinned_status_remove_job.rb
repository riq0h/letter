# frozen_string_literal: true

class SendPinnedStatusRemoveJob < ApplicationJob
  include ActivityDistribution

  queue_as :default

  def perform(actor_id, object_id)
    actor = Actor.find_by(id: actor_id)
    object = ActivityPubObject.find_by(id: object_id)

    return unless actor&.local?
    return unless object

    remove_activity = build_remove_activity(actor, object)
    distribute_activity(remove_activity, actor)
  end

  private

  def build_remove_activity(actor, object)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{actor.ap_id}#remove-#{object.id}-#{Time.current.to_i}",
      'type' => 'Remove',
      'actor' => actor.ap_id,
      'object' => object.ap_id,
      'target' => "#{actor.ap_id}/collections/featured",
      'published' => Time.current.iso8601
    }
  end
end
