# frozen_string_literal: true

module StatusActivityHandlers
  extend ActiveSupport::Concern

  private

  def create_like_activity(status)
    like_activity = current_user.activities.create!(
      ap_id: generate_like_activity_ap_id(status),
      activity_type: 'Like',
      object: status,
      target_ap_id: status.ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )

    # ステータスオーナーへの連合配信をキューに追加
    return unless status.actor != current_user && !status.actor.local?

    SendActivityJob.perform_later(like_activity.id, [status.actor.inbox_url])
  end

  def create_undo_like_activity(status, _favourite)
    undo_activity = current_user.activities.create!(
      ap_id: generate_undo_like_activity_ap_id(status),
      activity_type: 'Undo',
      target_ap_id: generate_like_activity_ap_id(status),
      published_at: Time.current,
      local: true,
      processed: true
    )

    # ステータスオーナーへの連合配信をキューに追加
    return unless status.actor != current_user && !status.actor.local?

    SendActivityJob.perform_later(undo_activity.id, [status.actor.inbox_url])
  end

  def generate_like_activity_ap_id(status)
    "#{status.ap_id}#like-#{current_user.id}-#{Time.current.to_i}"
  end

  def generate_undo_like_activity_ap_id(status)
    "#{status.ap_id}#undo-like-#{current_user.id}-#{Time.current.to_i}"
  end

  def create_announce_activity(status)
    announce_activity = build_announce_activity(status)
    deliver_announce_activity(announce_activity, status)
  end

  def build_announce_activity(status)
    current_user.activities.create!(
      ap_id: generate_announce_activity_ap_id(status),
      activity_type: 'Announce',
      target_ap_id: status.ap_id,
      published_at: Time.current,
      local: true
    )
  end

  def deliver_announce_activity(announce_activity, status)
    target_inboxes = collect_announce_target_inboxes(status)
    return unless target_inboxes.any?

    SendActivityJob.perform_later(announce_activity.id, target_inboxes.uniq)
  end

  def collect_announce_target_inboxes(status)
    target_inboxes = []

    # ステータスオーナーのinboxを追加
    target_inboxes << status.actor.inbox_url if status.actor != current_user && !status.actor.local?

    # パブリックアナウンスのフォロワー inboxを追加
    if status.visibility == 'public'
      follower_inboxes = current_user.followers.where(local: false).pluck(:inbox_url)
      target_inboxes.concat(follower_inboxes)
    end

    target_inboxes
  end

  def create_undo_announce_activity(status, _reblog)
    undo_activity = build_undo_announce_activity(status)
    deliver_undo_announce_activity(undo_activity, status)
  end

  def build_undo_announce_activity(status)
    current_user.activities.create!(
      ap_id: generate_undo_announce_activity_ap_id(status),
      activity_type: 'Undo',
      target_ap_id: generate_announce_activity_ap_id(status),
      published_at: Time.current,
      local: true,
      processed: true
    )
  end

  def deliver_undo_announce_activity(undo_activity, status)
    target_inboxes = collect_announce_target_inboxes(status)
    return unless target_inboxes.any?

    SendActivityJob.perform_later(undo_activity.id, target_inboxes.uniq)
  end

  def generate_announce_activity_ap_id(_status)
    "#{Rails.application.config.activitypub.base_url}/users/#{current_user.username}/activities/announce-#{current_user.id}-#{Time.current.to_i}"
  end

  def generate_undo_announce_activity_ap_id(_status)
    base_url = Rails.application.config.activitypub.base_url
    username = current_user.username
    user_id = current_user.id
    timestamp = Time.current.to_i
    "#{base_url}/users/#{username}/activities/undo-announce-#{user_id}-#{timestamp}"
  end
end
