# frozen_string_literal: true

class UndoProcessor
  include ActivityPubUtilityHelpers

  def initialize(target_activity)
    @target_activity = target_activity
  end

  def process!
    case @target_activity.activity_type
    when 'Follow'
      undo_follow
    when 'Like'
      undo_like
    when 'Announce'
      undo_announce
    end
  end

  private

  attr_reader :target_activity

  def undo_follow
    follow = Follow.find_by(follow_activity_ap_id: target_activity.ap_id)
    follow&.destroy
  end

  def undo_like
    return unless target_activity.target_ap_id

    target_obj = find_target_object(target_activity.target_ap_id)
    return unless target_obj

    process_like_undo(target_obj)
  end

  def undo_announce
    return unless target_activity.target_ap_id

    target_obj = find_target_object(target_activity.target_ap_id)
    return unless target_obj

    process_announce_undo(target_obj)
  end

  def process_like_undo(target_obj)
    ActiveRecord::Base.transaction do
      favourite = find_favourite(target_obj)
      favourite&.destroy
      target_activity.destroy

      log_like_undo(favourite)
    end
  end

  def process_announce_undo(target_obj)
    ActiveRecord::Base.transaction do
      reblog = find_reblog(target_obj)
      reblog&.destroy
      target_activity.destroy

      log_announce_undo(reblog)
    end
  end

  def find_favourite(target_obj)
    Favourite.find_by(actor: target_activity.actor, object: target_obj)
  end

  def find_reblog(target_obj)
    Reblog.find_by(actor: target_activity.actor, object: target_obj)
  end

  def log_like_undo(favourite)
    Rails.logger.info "❤️ Like undone: Activity #{target_activity.id} deleted, Favourite #{favourite&.id} deleted"
  end

  def log_announce_undo(reblog)
    Rails.logger.info "📢 Announce undone: Activity #{target_activity.id} deleted, Reblog #{reblog&.id} deleted"
  end
end
