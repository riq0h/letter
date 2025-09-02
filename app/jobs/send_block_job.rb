# frozen_string_literal: true

class SendBlockJob < ApplicationJob
  queue_as :default

  def perform(block, attempt = 1)
    block_activity = build_block_activity(block)
    result = send_block_activity(block_activity, block)

    handle_response(result[:success], block, attempt)
  rescue StandardError => e
    Rails.logger.error "💥 Block job error: #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")

    handle_failure(block, attempt)
  end

  private

  def build_block_activity(block)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'Block',
      'id' => generate_block_activity_id(block),
      'actor' => block.actor.ap_id,
      'object' => block.target_actor.ap_id,
      'published' => Time.current.iso8601
    }
  end

  def send_block_activity(activity, block)
    sender = ActivitySender.new

    # Shared inboxを優先的に使用
    target_inbox = block.target_actor.shared_inbox_url.presence || block.target_actor.inbox_url

    Rails.logger.info "🚫 Sending Block activity to: #{target_inbox}"

    sender.send_activity(
      activity: activity,
      target_inbox: target_inbox,
      signing_actor: block.actor
    )
  end

  def handle_response(success, block, attempt)
    if success
      Rails.logger.info "✅ Block activity sent successfully for block #{block.id}"
    else
      handle_failure(block, attempt)
    end
  end

  def handle_failure(block, attempt)
    Rails.logger.error "❌ Failed to send Block activity for block #{block.id} (attempt #{attempt}/3)"

    if attempt < 3
      # アクター情報を更新してからリトライ
      if should_refresh_actor?(attempt)
        Rails.logger.info "🔄 Attempting to refresh actor data for #{block.target_actor.ap_id}"
        refresh_actor_data(block.target_actor)
      end

      Rails.logger.info "🔄 Scheduling retry #{attempt + 1}/3 in 30 seconds for block #{block.id}"
      SendBlockJob.set(wait: 30.seconds).perform_later(block, attempt + 1)
    else
      Rails.logger.error "💥 Block sending failed permanently for block #{block.id} after 3 attempts"
    end
  end

  def should_refresh_actor?(attempt)
    attempt == 1
  end

  def refresh_actor_data(actor)
    fetcher = ActorFetcher.new
    updated_actor = fetcher.fetch_and_create(actor.ap_id)
    Rails.logger.info "✅ Actor data refreshed for #{actor.ap_id}" if updated_actor && updated_actor != actor
  rescue StandardError => e
    Rails.logger.warn "Failed to refresh actor data: #{e.message}"
  end

  def generate_block_activity_id(_block)
    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end
end
