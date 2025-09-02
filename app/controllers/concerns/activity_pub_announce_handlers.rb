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
    object = @activity['object']
    object.is_a?(Hash) ? object['id'] : object
  end

  def create_or_update_announce(target_object)
    return if announce_already_exists?(target_object)

    create_new_announce(target_object)
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
    ActiveRecord::Base.transaction do
      reblog = create_reblog_record(target_object)
      announce_activity = create_announce_activity_record(target_object)

      log_announce_creation(reblog, announce_activity, target_object)
    end
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
end
