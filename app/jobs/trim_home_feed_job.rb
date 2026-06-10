# frozen_string_literal: true

# home_feed_entries（キャッシュDB）の定期トリム。
# フィードはプライマリDBから再構築可能なキャッシュだが、トリム処理がないと
# 無限に成長する（運用6日時点で62万行を確認）。直近KEEP_ENTRIES件のみ残す。
class TrimHomeFeedJob < ApplicationJob
  queue_as :default

  KEEP_ENTRIES = 2000
  BATCH_SIZE = 10_000

  def perform
    cutoff = HomeFeedEntry.order(sort_id: :desc).offset(KEEP_ENTRIES).limit(1).pick(:sort_id)
    return unless cutoff

    deleted_total = 0
    loop do
      deleted = HomeFeedEntry.where(sort_id: ..cutoff).limit(BATCH_SIZE).delete_all
      deleted_total += deleted
      break if deleted < BATCH_SIZE
    end

    Rails.logger.info "🧹 Home feed trimmed: #{deleted_total} entries removed" if deleted_total.positive?
  end
end
