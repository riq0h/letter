# frozen_string_literal: true

class HomeFeedManager
  class << self
    def add_status(object)
      return unless eligible_status?(object)
      return unless should_appear_in_feed?(object)

      HomeFeedEntry.insert(
        { sort_id: object.id.to_s, object_id: object.id.to_s, reblog_id: nil,
          actor_id: object.actor_id, created_at: Time.current },
        unique_by: :sort_id
      )
    rescue StandardError => e
      Rails.logger.warn "[HomeFeed] Failed to add status #{object.id}: #{e.message}"
    end

    def add_reblog(reblog)
      return unless reblog
      return unless followed_actor_ids.include?(reblog.actor_id)
      return unless %w[public unlisted].include?(reblog.object&.visibility)

      HomeFeedEntry.insert(
        { sort_id: reblog.timeline_id, object_id: reblog.object_id.to_s, reblog_id: reblog.id,
          actor_id: reblog.actor_id, created_at: Time.current },
        unique_by: :sort_id
      )
    rescue StandardError => e
      Rails.logger.warn "[HomeFeed] Failed to add reblog #{reblog.id}: #{e.message}"
    end

    def remove_by_object(object_id)
      HomeFeedEntry.where(object_id: object_id.to_s).delete_all
    rescue StandardError => e
      Rails.logger.warn "[HomeFeed] Failed to remove object #{object_id}: #{e.message}"
    end

    def remove_reblog(reblog_id)
      HomeFeedEntry.where(reblog_id: reblog_id).delete_all
    rescue StandardError => e
      Rails.logger.warn "[HomeFeed] Failed to remove reblog #{reblog_id}: #{e.message}"
    end

    def remove_by_actor(actor_id)
      HomeFeedEntry.where(actor_id: actor_id).delete_all
    rescue StandardError => e
      Rails.logger.warn "[HomeFeed] Failed to remove actor #{actor_id}: #{e.message}"
    end

    def populated?
      HomeFeedEntry.exists?
    rescue StandardError
      false
    end

    def backfill!
      user = local_user
      return unless user

      Rails.logger.info '[HomeFeed] Starting backfill...'

      backfill_statuses(user)
      backfill_reblogs(user)

      Rails.logger.info "[HomeFeed] Backfill complete. Total entries: #{HomeFeedEntry.count}"
    end

    def followed_actor_ids
      user = local_user
      return [] unless user

      user.followed_actors.pluck(:id) + [user.id]
    end

    private

    def local_user
      @local_user = nil # 毎回リセット（クラスメソッドなのでキャッシュが残る可能性）
      Actor.find_by(local: true)
    end

    def followed_tag_ids
      user = local_user
      return [] unless user

      user.followed_tags.pluck(:tag_id)
    end

    def eligible_status?(object)
      return false unless object
      return false unless %w[Note Question].include?(object.object_type)
      return false if object.is_pinned_only

      true
    end

    def should_appear_in_feed?(object)
      # フォロー中アクター or 自分自身の投稿
      return true if followed_actor_ids.include?(object.actor_id)

      # フォロー中タグにマッチ（publicのみ）
      tag_ids = followed_tag_ids
      return true if tag_ids.any? && object.visibility == 'public' && ObjectTag.exists?(object_id: object.id, tag_id: tag_ids)

      false
    end

    def backfill_statuses(user)
      f_ids = user.followed_actors.pluck(:id) + [user.id]
      f_tag_ids = user.followed_tags.pluck(:tag_id)

      # フォロー中アクターの投稿
      ActivityPubObject.where(actor_id: f_ids, object_type: %w[Note Question], is_pinned_only: false)
                       .order(id: :desc)
                       .find_in_batches(batch_size: 1000) do |batch|
                         entries = batch.map do |obj|
                           { sort_id: obj.id.to_s, object_id: obj.id.to_s, reblog_id: nil,
                             actor_id: obj.actor_id, created_at: obj.created_at }
                         end
                         HomeFeedEntry.insert_all(entries, unique_by: :sort_id) if entries.any?
      end

      # フォロー中タグの投稿（publicのみ）
      return unless f_tag_ids.any?

      tag_object_ids = ObjectTag.where(tag_id: f_tag_ids).pluck(:object_id)
      return unless tag_object_ids.any?

      ActivityPubObject.where(id: tag_object_ids, object_type: %w[Note Question],
                              is_pinned_only: false, visibility: 'public')
                       .where.not(actor_id: f_ids) # 既にフォロー中アクターで追加済みを除外
                       .find_in_batches(batch_size: 1000) do |batch|
                         entries = batch.map do |obj|
                           { sort_id: obj.id.to_s, object_id: obj.id.to_s, reblog_id: nil,
                             actor_id: obj.actor_id, created_at: obj.created_at }
                         end
                         HomeFeedEntry.insert_all(entries, unique_by: :sort_id) if entries.any?
      end
    end

    def backfill_reblogs(user)
      f_ids = user.followed_actors.pluck(:id) + [user.id]

      Reblog.joins(:object)
            .where(actor_id: f_ids)
            .where(objects: { visibility: %w[public unlisted] })
            .find_in_batches(batch_size: 1000) do |batch|
              entries = batch.map do |reblog|
                { sort_id: reblog.timeline_id, object_id: reblog.object_id.to_s, reblog_id: reblog.id,
                  actor_id: reblog.actor_id, created_at: reblog.created_at }
              end
              HomeFeedEntry.insert_all(entries, unique_by: :sort_id) if entries.any?
      end
    end
  end
end
