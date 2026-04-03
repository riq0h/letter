# frozen_string_literal: true

class AnnounceProcessorJob < ApplicationJob
  include ActivityPubUtilityHelpers

  queue_as :default
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.minutes, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(activity_data, sender_id)
    @activity = activity_data
    @sender = Actor.find(sender_id)

    Rails.logger.info "🔄 Background processing Announce activity from #{@sender.username}"

    object_ap_id = extract_announce_object_id
    return unless object_ap_id

    target_object = find_target_object(object_ap_id)
    return unless target_object

    create_announce_records(target_object)
  end

  private

  def extract_announce_object_id
    extract_activity_object_id(@activity['object'])
  end

  def create_announce_records(target_object)
    if target_object.actor.local?
      # 自分の投稿へのAnnounce: フル保存
      return if announce_already_exists?(target_object)

      reblog = nil
      ActiveRecord::Base.transaction do
        reblog = create_reblog_record(target_object)
        announce_activity = create_announce_activity_record(target_object)

        Rails.logger.info "📢 Background Announce created: Reblog #{reblog.id}, Activity #{announce_activity.id}"
      end
      HomeFeedManager.add_reblog(reblog) if reblog
    else
      # 他人の投稿へのAnnounce: カウンタのみ更新
      ActivityPubObject.update_counters(target_object.id, reblogs_count: 1)
      Rails.logger.info "📢 Reblogs count incremented for remote object #{target_object.id}"
    end
  end

  def announce_already_exists?(target_object)
    Reblog.exists?(actor: @sender, object: target_object) ||
      target_object.activities.exists?(actor: @sender, activity_type: 'Announce')
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
end
