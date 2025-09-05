# frozen_string_literal: true

class ActivityProcessor
  include ActivityPubUtilityHelpers

  PROCESSOR_MAP = {
    'Create' => :process_create_activity,
    'Follow' => :process_follow_activity,
    'Accept' => :process_accept_activity,
    'Like' => :process_like_activity,
    'Announce' => :process_announce_activity,
    'Delete' => :process_delete_activity,
    'Undo' => :process_undo_activity
  }.freeze

  def initialize(activity)
    @activity = activity
  end

  def process!
    processor_method = PROCESSOR_MAP[@activity.activity_type]

    if processor_method
      send(processor_method)
    else
      log_unknown_activity_type
    end
  end

  private

  attr_reader :activity

  def process_create_activity
    return unless activity.object

    # 投稿数更新
    activity.actor.update_posts_count! if activity.object.object_type == 'Note'
  end

  def process_follow_activity
    target_actor = find_target_actor
    return unless target_actor

    create_or_update_follow(target_actor)
  end

  def process_accept_activity
    follow_activity = find_follow_activity
    return unless follow_activity

    accept_follow_request
  end

  def process_like_activity
    target_obj = find_target_object(activity.target_ap_id)
    return unless target_obj

    # Favouriteレコードを作成（通知とカウント更新は自動実行される）
    Favourite.find_or_create_by!(
      actor: activity.actor,
      object: target_obj
    )
  end

  def process_announce_activity
    target_obj = find_target_object(activity.target_ap_id)
    return unless target_obj

    # Reblogレコードを作成（通知とカウント更新は自動実行される）
    Reblog.find_or_create_by!(
      actor: activity.actor,
      object: target_obj
    )
  end

  def process_delete_activity
    target = find_target_by_ap_id
    return unless target

    delete_target(target)
  end

  def process_undo_activity
    target_activity = find_target_activity
    return unless target_activity

    UndoProcessor.new(target_activity).process!
  end

  def find_target_actor
    return unless activity.target_ap_id

    Actor.find_by(ap_id: activity.target_ap_id)
  end

  def find_target_activity
    return unless activity.target_ap_id

    Activity.find_by(ap_id: activity.target_ap_id)
  end

  def find_target_by_ap_id
    return unless activity.target_ap_id

    ActivityPubObject.find_by(ap_id: activity.target_ap_id) ||
      Actor.find_by(ap_id: activity.target_ap_id) ||
      Activity.find_by(ap_id: activity.target_ap_id)
  end

  def find_follow_activity
    return unless activity.target_ap_id

    Activity.find_by(ap_id: activity.target_ap_id, activity_type: 'Follow')
  end

  def create_or_update_follow(target_actor)
    follow = Follow.find_or_initialize_by(
      actor: activity.actor,
      target_actor: target_actor
    )

    follow.assign_attributes(
      ap_id: activity.ap_id,
      follow_activity_ap_id: activity.ap_id,
      accepted: target_actor.local? && !target_actor.manually_approves_followers
    )

    follow.save!
  end

  def accept_follow_request
    follow = Follow.find_by(follow_activity_ap_id: activity.target_ap_id)
    return unless follow

    follow.update!(
      accepted: true,
      accepted_at: Time.current,
      accept_activity_ap_id: activity.ap_id
    )
  end

  def delete_target(target)
    case target
    when ActivityPubObject
      target.destroy
      target.actor.update_posts_count! if target.object_type == 'Note'
    when Actor
      target.update!(suspended: true)
    end
  end

  def log_unknown_activity_type
    Rails.logger.warn "Unknown activity type: #{activity.activity_type}"
  end
end
