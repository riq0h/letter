# frozen_string_literal: true

class SendFollowJob < ApplicationJob
  include ActorRefreshOnRetry

  queue_as :default

  # SolidQueueの重複制約エラーを回避するため、retry_onを使わない

  def perform(follow, attempt = 1)
    follow_activity = build_follow_activity(follow)
    result = send_follow_activity(follow_activity, follow)

    handle_response(result[:success], follow, attempt)
  rescue StandardError => e
    Rails.logger.error "💥 Follow job error: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")

    # 例外が発生した場合も失敗として扱う
    handle_failure(follow, attempt)
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

    target_inbox = follow.target_actor.preferred_inbox

    Rails.logger.info "🔍 Using inbox: #{target_inbox} (shared: #{follow.target_actor.shared_inbox_url.present?})"

    sender.send_activity(
      activity: activity,
      target_inbox: target_inbox,
      signing_actor: follow.actor
    )
  end

  def handle_response(success, follow, attempt)
    if success
      Rails.logger.info "✅ Follow activity sent successfully for follow #{follow.id}"
      # フォローリクエストは送信済みだが、承認待ち状態を維持
    else
      handle_failure(follow, attempt)
    end
  end

  def handle_failure(follow, attempt)
    Rails.logger.error "❌ Failed to send Follow activity for follow #{follow.id} (attempt #{attempt}/3)"

    if attempt < 3
      # 404エラーの場合はアクター情報を更新してからリトライ
      if should_refresh_actor?(attempt)
        Rails.logger.info "🔄 Attempting to refresh actor data for #{follow.target_actor.ap_id}"
        refresh_actor_data(follow.target_actor)
      end

      # 新しいジョブとして次の試行をスケジュール
      Rails.logger.info "🔄 Scheduling retry #{attempt + 1}/3 in 30 seconds for follow #{follow.id}"
      SendFollowJob.set(wait: 30.seconds).perform_later(follow, attempt + 1)
    else
      Rails.logger.error "💥 Follow sending failed permanently for follow #{follow.id} after 3 attempts"
      # 永続的に失敗した場合はフォロー関係を削除
      follow.destroy
    end
  end
end
