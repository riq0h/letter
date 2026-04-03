# frozen_string_literal: true

module ActivityPubAnnounceHandlers
  extend ActiveSupport::Concern

  private

  # Announce Activity処理（ブースト）
  def handle_announce_activity
    Rails.logger.info '📢 Processing Announce activity'

    object_ap_id = extract_announce_object_id
    return head(:accepted) unless object_ap_id

    target_object = find_local_target_object(object_ap_id)

    unless target_object
      Rails.logger.info "📢 Target object not found locally, queuing for background fetch: #{object_ap_id}"
      AnnounceProcessorJob.perform_later(@activity, @sender.id)
      return head(:accepted)
    end

    create_or_update_announce(target_object)
    head :accepted
  end

  def extract_announce_object_id
    extract_activity_object_id(@activity['object'])
  end

  def create_or_update_announce(target_object)
    if target_object.actor.local?
      # 自分の投稿へのAnnounce: フル保存（通知+ホームフィード）
      return if announce_already_exists?(target_object)

      create_new_announce(target_object)
    else
      # 他人の投稿へのAnnounce: カウンタのみ更新
      increment_reblogs_count(target_object)
    end
  end

  def announce_already_exists?(target_object)
    existing_reblog = find_existing_reblog(target_object)
    existing_activity = find_existing_announce_activity(target_object)

    if existing_reblog || existing_activity
      Rails.logger.info "📢 Announce already exists: Reblog #{existing_reblog&.id}, Activity #{existing_activity&.id}"
      return true
    end

    false
  end

  def find_existing_reblog(target_object)
    Reblog.find_by(actor: @sender, object: target_object)
  end

  def find_existing_announce_activity(target_object)
    target_object.activities.find_by(actor: @sender, activity_type: 'Announce')
  end

  def create_new_announce(target_object)
    reblog = nil
    ActiveRecord::Base.transaction do
      reblog = create_reblog_record(target_object)
      announce_activity = create_announce_activity_record(target_object)

      log_announce_creation(reblog, announce_activity, target_object)
    end
    HomeFeedManager.add_reblog(reblog) if reblog
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info '📢 Announce already exists (concurrent request)'
  end

  def create_reblog_record(target_object)
    Reblog.create!(
      actor: @sender,
      object: target_object,
      ap_id: @activity['id']
    )
  end

  def create_announce_activity_record(target_object)
    target_object.activities.create!(
      actor: @sender,
      activity_type: 'Announce',
      ap_id: @activity['id'],
      target_ap_id: target_object.ap_id,
      published_at: Time.current,
      local: false,
      processed: true
    )
  end

  def log_announce_creation(reblog, announce_activity, target_object)
    Rails.logger.info "📢 Announce created: Reblog #{reblog.id}, Activity #{announce_activity.id}, " \
                      "reblogs_count updated to #{target_object.reload.reblogs_count}"
  end

  def find_local_target_object(object_ap_id)
    ActivityPubObject.find_by(ap_id: object_ap_id)
  end

  def increment_reblogs_count(target_object)
    ActivityPubObject.update_counters(target_object.id, reblogs_count: 1)
    Rails.logger.info "📢 Reblogs count incremented for remote object #{target_object.id}"
  end
end
