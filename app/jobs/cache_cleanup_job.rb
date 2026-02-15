# frozen_string_literal: true

# 期限切れのキャッシュとファイルをクリーンアップするジョブ
class CacheCleanupJob < ApplicationJob
  queue_as :low_priority

  def perform
    cleanup_expired_cache_files
    cleanup_orphaned_blobs
  rescue StandardError => e
    Rails.logger.error "CacheCleanupJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def cleanup_expired_cache_files
    expired_count = 0

    cutoff_date = RemoteImageCacheService::CACHE_DURATION.ago

    old_blobs = ActiveStorage::Blob
                .where(created_at: ...cutoff_date)
                .where('key LIKE ?', 'img/%')

    old_blobs.find_each do |blob|
      attachments = ActiveStorage::Attachment.where(blob: blob)

      if attachments.empty? || attachments.all? { |att| att.record.is_a?(MediaAttachment) && !att.record.actor.local? }
        blob.purge
        expired_count += 1
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to purge blob #{blob.id}: #{e.message}"
    end

    Rails.logger.info "CacheCleanupJob: purged #{expired_count} expired cache files"
  end

  def cleanup_orphaned_blobs
    orphaned_blobs = ActiveStorage::Blob
                     .where(created_at: ...RemoteImageCacheService::CACHE_DURATION.ago)
                     .where('key LIKE ?', 'img/%')
                     .left_joins(:attachments)
                     .where(active_storage_attachments: { id: nil })

    count = orphaned_blobs.count
    orphaned_blobs.find_each do |blob|
      blob.purge
    rescue StandardError => e
      Rails.logger.warn "Failed to purge orphaned blob #{blob.id}: #{e.message}"
    end

    Rails.logger.info "CacheCleanupJob: purged #{count} orphaned blobs"
  end
end
