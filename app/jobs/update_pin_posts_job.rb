# frozen_string_literal: true

class UpdatePinPostsJob < ApplicationJob
  queue_as :default

  def perform(actor_id)
    actor = Actor.find(actor_id)
    return unless actor && !actor.local? && actor.featured_url.present?

    ActiveRecord::Base.transaction do
      # 既存のpin投稿を削除
      actor.pinned_statuses.destroy_all

      # 新しいpin投稿を取得
      fetcher = FeaturedCollectionFetcher.new
      fetcher.fetch_for_actor(actor)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ Actor #{actor_id} not found for pin posts update"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to update pin posts for actor #{actor_id}: #{e.message}"
  end
end
