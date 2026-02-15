# frozen_string_literal: true

# Mastodonの UpdateDistributionWorker を参考にした実装
class SendProfileUpdateJob < ApplicationJob
  include ActivityDistribution

  queue_as :push

  def perform(actor_id)
    actor = Actor.find_by(id: actor_id)
    return if actor.nil? || !actor.local?

    update_activity = build_update_activity(actor)
    distribute_activity(update_activity, actor)
  end

  private

  def build_update_activity(actor)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{actor.ap_id}#updates/#{Time.current.to_i}",
      'type' => 'Update',
      'actor' => actor.ap_id,
      'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      'object' => actor.to_activitypub
    }
  end
end
