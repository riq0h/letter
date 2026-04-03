# frozen_string_literal: true

class UpdatePinPostsJob < ApplicationJob
  queue_as :default

  def perform(actor_id)
    actor = Actor.find(actor_id)
    return unless actor && !actor.local? && actor.featured_url.present?

    # フェッチ成功後に古いデータを置き換える（失敗時はデータ保持）
    old_ids = actor.pinned_statuses.pluck(:id)
    new_objects = FeaturedCollectionFetcher.new.fetch_for_actor_fresh(actor)

    actor.pinned_statuses.where(id: old_ids).destroy_all if new_objects.any?
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ Actor #{actor_id} not found for pin posts update"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to update pin posts for actor #{actor_id}: #{e.message}"
  end
end
