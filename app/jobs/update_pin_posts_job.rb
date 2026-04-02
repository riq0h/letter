# frozen_string_literal: true

class UpdatePinPostsJob < ApplicationJob
  queue_as :default

  def perform(actor_id)
    actor = Actor.find(actor_id)
    return unless actor && !actor.local? && actor.featured_url.present?

    # 先にHTTP通信でピン投稿データを取得（ロックなし）
    fetcher = FeaturedCollectionFetcher.new
    # 既存のpin投稿を削除してからfetchする（fetchは既存があればスキップするため）
    actor.pinned_statuses.destroy_all

    # fetchはHTTP通信を含むがトランザクション外で実行
    fetcher.fetch_for_actor(actor)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "⚠️ Actor #{actor_id} not found for pin posts update"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to update pin posts for actor #{actor_id}: #{e.message}"
  end
end
