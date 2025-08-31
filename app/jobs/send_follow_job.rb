# frozen_string_literal: true

class SendFollowJob < ApplicationJob
  queue_as :default

  def perform(follow)
    follow_activity = build_follow_activity(follow)
    result = send_follow_activity(follow_activity, follow)

    handle_response(result[:success], follow)
  rescue StandardError => e
    handle_error(e, 'Follow job error')
  end

  private

  def build_follow_activity(follow)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'Follow',
      'id' => follow.follow_activity_ap_id,
      'actor' => follow.actor.ap_id,
      'object' => follow.target_actor.ap_id,
      'published' => Time.current.iso8601
    }
  end

  def send_follow_activity(activity, follow)
    sender = ActivitySender.new
    sender.send_activity(
      activity: activity,
      target_inbox: follow.target_actor.inbox_url,
      signing_actor: follow.actor
    )
  end

  def handle_response(success, follow)
    if success
      # フォローリクエストは送信済みだが、承認待ち状態を維持
    else
      handle_failure(follow)
    end
  end

  def handle_failure(follow)
    Rails.logger.error "❌ Failed to send Follow activity for follow #{follow.id}"

    if executions < 3
      # 404エラーの場合はアクター情報を更新してからリトライ
      if should_refresh_actor?(follow)
        Rails.logger.info "🔄 Attempting to refresh actor data for #{follow.target_actor.ap_id}"
        refresh_actor_data(follow.target_actor)
      end

      retry_job(wait: 30.seconds)
    else
      Rails.logger.error "💥 Follow sending failed permanently for follow #{follow.id}"
      # 永続的に失敗した場合はフォロー関係を削除
      follow.destroy
    end
  end

  def should_refresh_actor?(_follow)
    # 初回失敗時のみアクター情報を更新
    executions == 1
  end

  def refresh_actor_data(actor)
    fetcher = ActorFetcher.new
    fetcher.update_actor_from_remote(actor.ap_id)
  rescue StandardError => e
    Rails.logger.warn "Failed to refresh actor data: #{e.message}"
  end
end
