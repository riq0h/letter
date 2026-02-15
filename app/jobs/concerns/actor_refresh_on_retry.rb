# frozen_string_literal: true

# ActivityPub配信ジョブ共通のリトライ時アクター更新ロジック
module ActorRefreshOnRetry
  extend ActiveSupport::Concern

  private

  def should_refresh_actor?(attempt)
    # 初回失敗時のみアクター情報を更新
    attempt == 1
  end

  def refresh_actor_data(actor)
    fetcher = ActorFetcher.new
    updated_actor = fetcher.fetch_and_create(actor.ap_id)
    Rails.logger.info "✅ Actor data refreshed for #{actor.ap_id}" if updated_actor && updated_actor != actor
  rescue StandardError => e
    Rails.logger.warn "Failed to refresh actor data: #{e.message}"
  end
end
