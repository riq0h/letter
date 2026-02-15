# frozen_string_literal: true

class SendPinnedStatusAddJob < ApplicationJob
  include ActivityDistribution

  queue_as :default

  def perform(actor_id, object_id)
    actor = Actor.find_by(id: actor_id)
    object = ActivityPubObject.find_by(id: object_id)

    return unless actor&.local?
    return unless object

    add_activity = build_add_activity(actor, object)
    distribute_activity(add_activity, actor)
  end

  private

  def build_add_activity(actor, object)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{actor.ap_id}#add-#{object.id}-#{Time.current.to_i}",
      'type' => 'Add',
      'actor' => actor.ap_id,
      'object' => object.ap_id,
      'target' => "#{actor.ap_id}/collections/featured",
      'published' => Time.current.iso8601
    }
  end
end
