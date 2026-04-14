# frozen_string_literal: true

class ReblogFetchJob < ApplicationJob
  queue_as :default
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 5.minutes, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(activity_data, sender_id)
    @activity = activity_data
    @sender = Actor.find(sender_id)

    object_ap_id = extract_object_ap_id
    return unless object_ap_id

    target_object = find_or_fetch_target(object_ap_id)
    return unless target_object

    create_lightweight_reblog(target_object)
  end

  private

  def extract_object_ap_id
    object = @activity['object']
    case object
    when String then object
    when Hash then object['id']
    end
  end

  def find_or_fetch_target(ap_id)
    ActivityPubObject.find_by(ap_id: ap_id) ||
      Search::RemoteResolverService.new.resolve_remote_status(ap_id)
  end

  def create_lightweight_reblog(target_object)
    return if Reblog.exists?(actor: @sender, object: target_object)

    reblog = Reblog.create!(
      actor: @sender,
      object: target_object,
      ap_id: @activity['id']
    )
    HomeFeedManager.add_reblog(reblog)
    Rails.logger.info "📢 Reblog created: #{reblog.id} for object #{target_object.id}"
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.debug { '📢 Reblog already exists' }
  end
end
