# frozen_string_literal: true

class RelayDistributionService
  include RelayActorManagement

  def initialize
    @activity_sender = ActivitySender.new
  end

  def distribute_to_relays(activity_pub_object)
    return unless should_distribute?(activity_pub_object)

    enabled_relays = Relay.enabled
    return if enabled_relays.empty?

    Rails.logger.info "📡 Distributing #{activity_pub_object.object_type} to #{enabled_relays.count} relay(s)"

    enabled_relays.each do |relay|
      distribute_to_relay(activity_pub_object, relay)
    end
  end

  private

  def should_distribute?(activity_pub_object)
    return false unless activity_pub_object&.object_type == 'Note'
    return false unless activity_pub_object.local?

    activity_pub_object.visibility == 'public'
  end

  def distribute_to_relay(activity_pub_object, relay)
    # リレー用のAnnounceアクティビティを作成
    announce_activity = create_announce_activity(activity_pub_object, relay)

    # リレーに送信
    result = @activity_sender.send_activity(
      activity: announce_activity,
      target_inbox: relay.inbox_url,
      signing_actor: local_actor
    )

    if result[:success]
      relay.update_column(:delivery_attempts, 0) if relay.delivery_attempts.positive?
      Rails.logger.info "✅ Successfully distributed to relay: #{relay.domain}"
    else
      Rails.logger.error "❌ Failed to distribute to relay: #{relay.domain}"
      increment_relay_error_count(relay)
    end
  rescue StandardError => e
    Rails.logger.error "💥 Relay distribution error for #{relay.domain}: #{e.message}"
    increment_relay_error_count(relay)
  end

  def create_announce_activity(activity_pub_object, relay)
    local_actor_instance = local_actor
    activity_id = "#{local_actor_instance.ap_id}#announces/relay/#{SecureRandom.hex(16)}"

    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => activity_id,
      'type' => 'Announce',
      'actor' => local_actor_instance.ap_id,
      'published' => Time.current.iso8601,
      'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      'cc' => [relay.actor_uri],
      'object' => activity_pub_object.ap_id
    }
  end

  def local_actor
    @local_actor ||= super
  end

  def increment_relay_error_count(relay)
    relay.increment!(:delivery_attempts)

    # 3回連続エラーで一時的に無効化
    return unless relay.delivery_attempts >= 3

    relay.update!(
      state: 'idle',
      last_error: 'Too many delivery failures, disabled relay',
      delivery_attempts: 0
    )
    Rails.logger.warn "⚠️ Relay #{relay.domain} disabled due to repeated failures"
  end
end
