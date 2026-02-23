# frozen_string_literal: true

module ActivityPubCollectionHandlers
  extend ActiveSupport::Concern

  private

  # Add Activity処理（ピン留め）
  def handle_add_activity
    return head(:accepted) unless featured_collection_target?

    object_ap_id = extract_activity_object_id(@activity['object'])
    return head(:accepted) unless object_ap_id

    object = find_or_fetch_object(object_ap_id)
    return head(:accepted) unless object

    create_pinned_status(@sender, object)
    head :accepted
  end

  # Remove Activity処理（ピン留め解除）
  def handle_remove_activity
    return head(:accepted) unless featured_collection_target?

    object_ap_id = extract_activity_object_id(@activity['object'])
    return head(:accepted) unless object_ap_id

    object = ActivityPubObject.find_by(ap_id: object_ap_id)
    return head(:accepted) unless object

    destroy_pinned_status(@sender, object)
    head :accepted
  end

  def featured_collection_target?
    target = @activity['target']
    return false unless target.is_a?(String)

    target.include?('featured')
  end

  def find_or_fetch_object(ap_id)
    object = ActivityPubObject.find_by(ap_id: ap_id)
    return object if object

    resolver = Search::RemoteResolverService.new
    resolver.resolve_remote_status_for_pinned(ap_id)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch pinned object #{ap_id}: #{e.message}"
    nil
  end

  def create_pinned_status(actor, object)
    return if PinnedStatus.exists?(actor: actor, object: object)

    PinnedStatus.create!(
      actor: actor,
      object: object,
      position: actor.pinned_statuses.count
    )

    Rails.logger.info "📌 Pinned status added: #{actor.username}@#{actor.domain} pinned #{object.ap_id}"
  rescue StandardError => e
    Rails.logger.error "Failed to create pinned status: #{e.message}"
  end

  def destroy_pinned_status(actor, object)
    pinned = PinnedStatus.find_by(actor: actor, object: object)
    return unless pinned

    pinned.destroy
    Rails.logger.info "📌 Pinned status removed: #{actor.username}@#{actor.domain} unpinned #{object.ap_id}"
  rescue StandardError => e
    Rails.logger.error "Failed to destroy pinned status: #{e.message}"
  end
end
