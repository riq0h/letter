# frozen_string_literal: true

class CleanupUnavailableServerJob < ApplicationJob
  queue_as :default

  # 利用不可能なサーバのクリーンアップジョブ
  # @param unavailable_server_id [Integer] UnavailableServerのID
  def perform(unavailable_server_id)
    @unavailable_server = UnavailableServer.find(unavailable_server_id)

    Rails.logger.info "🧹 Starting cleanup for unavailable server: #{@unavailable_server.domain}"

    cleanup_relationships

    Rails.logger.info "✅ Cleanup completed for unavailable server: #{@unavailable_server.domain}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "❌ UnavailableServer #{unavailable_server_id} not found"
  rescue StandardError => e
    Rails.logger.error "💥 CleanupUnavailableServerJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def cleanup_relationships
    domain = @unavailable_server.domain

    # このドメインのユーザを取得
    domain_actors = Actor.where(domain: domain)
    actor_ids = domain_actors.pluck(:id)

    return if actor_ids.empty?

    Rails.logger.info "🔍 Found #{actor_ids.count} users from domain #{domain}"

    # 影響を受けるローカルユーザIDを削除前に収集
    affected_local_actor_ids = collect_affected_local_actor_ids(actor_ids)

    # フォロー関係を削除
    cleanup_follows(actor_ids)

    # フォロワー数・フォロー数を更新（事前収集したIDを使用）
    update_relationship_counts(affected_local_actor_ids)
  end

  def collect_affected_local_actor_ids(domain_actor_ids)
    # ドメインユーザをフォローしているローカルユーザ
    followers_of_domain = Follow.where(target_actor_id: domain_actor_ids)
                                .joins(:actor)
                                .where(actors: { local: true })
                                .pluck(:actor_id)

    # ドメインユーザにフォローされているローカルユーザ
    followed_by_domain = Follow.where(actor_id: domain_actor_ids)
                               .joins(:target_actor)
                               .where(actors: { local: true })
                               .pluck(:target_actor_id)

    (followers_of_domain + followed_by_domain).uniq
  end

  def cleanup_follows(actor_ids)
    # このドメインのユーザがフォローしている関係を削除
    follows_by_domain_count = Follow.where(actor_id: actor_ids).count
    Follow.where(actor_id: actor_ids).delete_all

    # このドメインのユーザをフォローしている関係を削除
    follows_to_domain_count = Follow.where(target_actor_id: actor_ids).count
    Follow.where(target_actor_id: actor_ids).delete_all

    Rails.logger.info "🗑️ Removed #{follows_by_domain_count} follows by domain users"
    Rails.logger.info "🗑️ Removed #{follows_to_domain_count} follows to domain users"
  end

  def update_relationship_counts(affected_local_actor_ids)
    affected_local_actor_ids.each do |actor_id|
      actor = Actor.find_by(id: actor_id, local: true)
      next unless actor

      actor.update_followers_count!
      actor.update_following_count!
    end

    Rails.logger.info "📊 Updated relationship counts for #{affected_local_actor_ids.count} local users"
  end
end
