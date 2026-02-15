# frozen_string_literal: true

class SendUnblockJob < ApplicationJob
  include ActorRefreshOnRetry

  queue_as :default

  def perform(actor_ap_id, target_actor_ap_id, target_inbox_url, attempt = 1)
    actor = Actor.find_by(ap_id: actor_ap_id)
    target_actor = Actor.find_by(ap_id: target_actor_ap_id)

    return unless actor&.local? && target_actor

    unblock_activity = build_unblock_activity(actor, target_actor)
    result = send_unblock_activity(unblock_activity, target_inbox_url, actor)

    handle_response(result[:success], actor, target_actor, attempt)
  rescue StandardError => e
    Rails.logger.error "💥 Unblock job error: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")

    handle_failure(actor, target_actor, target_inbox_url, attempt)
  end

  private

  def build_unblock_activity(actor, target_actor)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'Undo',
      'id' => generate_undo_activity_id,
      'actor' => actor.ap_id,
      'object' => {
        'type' => 'Block',
        'id' => generate_block_activity_id,
        'actor' => actor.ap_id,
        'object' => target_actor.ap_id
      },
      'published' => Time.current.iso8601
    }
  end

  def send_unblock_activity(activity, target_inbox_url, signing_actor)
    sender = ActivitySender.new

    Rails.logger.info "🔓 Sending Undo Block activity to: #{target_inbox_url}"

    sender.send_activity(
      activity: activity,
      target_inbox: target_inbox_url,
      signing_actor: signing_actor
    )
  end

  def handle_response(success, actor, target_actor, attempt)
    if success
      Rails.logger.info "✅ Undo Block activity sent successfully from #{actor.ap_id} to #{target_actor.ap_id}"
    else
      handle_failure(actor, target_actor, target_actor.inbox_url, attempt)
    end
  end

  def handle_failure(actor, target_actor, target_inbox_url, attempt)
    return unless actor && target_actor

    Rails.logger.error "❌ Failed to send Undo Block activity from #{actor.ap_id} (attempt #{attempt}/3)"

    if attempt < 3
      # アクター情報を更新してからリトライ
      if should_refresh_actor?(attempt)
        Rails.logger.info "🔄 Attempting to refresh actor data for #{target_actor.ap_id}"
        refresh_actor_data(target_actor)
      end

      Rails.logger.info "🔄 Scheduling retry #{attempt + 1}/3 in 30 seconds"
      SendUnblockJob.set(wait: 30.seconds).perform_later(
        actor.ap_id,
        target_actor.ap_id,
        target_inbox_url,
        attempt + 1
      )
    else
      Rails.logger.error '💥 Undo Block sending failed permanently after 3 attempts'
    end
  end

  def generate_undo_activity_id
    ApIdGeneration.generate_ap_id
  end

  def generate_block_activity_id
    ApIdGeneration.generate_ap_id
  end
end
