# frozen_string_literal: true

module ActivityPubLikeHandlers
  extend ActiveSupport::Concern

  private

  # Like Activity処理
  def handle_like_activity
    Rails.logger.info '❤️ Processing Like activity'

    object_ap_id = extract_like_object_id
    return head(:accepted) unless object_ap_id

    target_object = find_target_object(object_ap_id)
    return head(:accepted) unless target_object

    create_or_update_like(target_object)
    head :accepted
  end

  def extract_like_object_id
    extract_activity_object_id(@activity['object'])
  end

  def create_or_update_like(target_object)
    return if like_already_exists?(target_object)

    create_new_like(target_object)
  end

  def like_already_exists?(target_object)
    existing_activity = find_existing_like_activity(target_object)
    existing_favourite = find_existing_favourite(target_object)

    if existing_activity || existing_favourite
      Rails.logger.info "❤️ Like already exists: Activity #{existing_activity&.id}, Favourite #{existing_favourite&.id}"
      return true
    end

    false
  end

  def find_existing_like_activity(target_object)
    target_object.activities.find_by(actor: @sender, activity_type: 'Like')
  end

  def find_existing_favourite(target_object)
    Favourite.find_by(actor: @sender, object: target_object)
  end

  def create_new_like(target_object)
    ActiveRecord::Base.transaction do
      like_activity = create_like_activity_record(target_object)
      favourite = create_favourite_record(target_object)

      log_like_creation(like_activity, favourite, target_object)
    end
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info '❤️ Like already exists (concurrent request)'
  end

  def create_like_activity_record(target_object)
    target_object.activities.create!(
      actor: @sender,
      activity_type: 'Like',
      ap_id: @activity['id'],
      target_ap_id: target_object.ap_id,
      published_at: Time.current,
      local: false,
      processed: true
    )
  end

  def create_favourite_record(target_object)
    Favourite.create!(
      actor: @sender,
      object: target_object,
      ap_id: @activity['id']
    )
  end

  def log_like_creation(like_activity, favourite, target_object)
    Rails.logger.info "❤️ Like created: Activity #{like_activity.id}, Favourite #{favourite.id}, " \
                      "favourites_count updated to #{target_object.reload.favourites_count}"
  end
end
