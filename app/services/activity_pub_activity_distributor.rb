# frozen_string_literal: true

class ActivityPubActivityDistributor
  def initialize(object)
    @object = object
  end

  def create_activity
    return unless should_create_activity?

    activity = Activity.create!(
      ap_id: generate_activity_id,
      activity_type: 'Create',
      actor: object.actor,
      target_ap_id: object.ap_id,
      published_at: object.published_at,
      local: true,
      processed: false
    )

    queue_activity_delivery(activity)
    activity
  end

  def create_update_activity
    return unless object.local?

    activity = Activity.create!(
      ap_id: generate_activity_id,
      activity_type: 'Update',
      actor: object.actor,
      target_ap_id: object.ap_id,
      published_at: Time.current,
      local: true,
      processed: false
    )

    queue_activity_delivery(activity)
    activity
  end

  def create_delete_activity
    return unless object.local?

    activity = Activity.create!(
      ap_id: generate_activity_id,
      activity_type: 'Delete',
      actor: object.actor,
      target_ap_id: object.ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )

    queue_activity_delivery(activity)
    activity
  end

  def create_quote_activity(quoted_object)
    return unless object.local?

    activity = Activity.create!(
      ap_id: generate_activity_id,
      activity_type: 'Create',
      actor: object.actor,
      target_ap_id: quoted_object.ap_id,
      published_at: object.published_at,
      local: true,
      processed: false
    )

    queue_activity_delivery(activity)
    activity
  end

  private

  attr_reader :object

  def should_create_activity?
    object.local? && %w[public unlisted].include?(object.visibility)
  end

  def generate_activity_id
    ApIdGeneration.generate_ap_id
  end

  def queue_activity_delivery(activity)
    return unless activity.local?

    # フォロワーへの配信
    if should_deliver_to_followers?
      inbox_urls = collect_follower_inboxes
      SendActivityJob.perform_later(activity.id, inbox_urls) if inbox_urls.any?
    end

    # リレーへの配信
    return unless should_distribute_to_relays?

    relay_inboxes = Relay.enabled.pluck(:inbox_url).compact
    SendActivityJob.perform_later(activity.id, relay_inboxes) if relay_inboxes.any?
  end

  def collect_follower_inboxes
    followers = object.actor.followers.where(local: false)
    shared_inboxes = followers.filter_map(&:shared_inbox_url).uniq
    individual_inboxes = followers.filter_map(&:inbox_url).uniq

    # shared_inboxがあるドメインの個別inboxを除外
    shared_domains = shared_inboxes.filter_map do |url|
      URI(url).host
    rescue URI::InvalidURIError
      nil
    end
    individual_inboxes.reject! do |url|
      shared_domains.include?(URI(url).host)
    rescue URI::InvalidURIError
      false
    end

    (shared_inboxes + individual_inboxes).uniq
  end

  def should_deliver_to_followers?
    %w[public unlisted].include?(object.visibility)
  end

  def should_distribute_to_relays?
    object.visibility == 'public' && object.in_reply_to_ap_id.blank?
  end
end
