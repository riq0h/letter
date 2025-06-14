# frozen_string_literal: true

module ActivityPubInteractionHandlers
  extend ActiveSupport::Concern

  private

  # Announce Activity処理（ブースト）
  def handle_announce_activity
    Rails.logger.info '📢 Processing Announce activity'

    object_ap_id = extract_announce_object_id
    return head(:accepted) unless object_ap_id

    target_object = find_target_object(object_ap_id)
    return head(:accepted) unless target_object

    create_or_update_announce(target_object)
    head :accepted
  end

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

  def extract_announce_object_id
    object = @activity['object']
    object.is_a?(Hash) ? object['id'] : object
  end

  def create_or_update_announce(target_object)
    # 既存のAnnounce（Reblog）をチェック
    existing_reblog = Reblog.find_by(
      actor: @sender,
      object: target_object
    )

    if existing_reblog
      Rails.logger.info "📢 Announce already exists: #{existing_reblog.id}"
      return
    end

    # 新しいReblogを作成
    reblog = Reblog.create!(
      actor: @sender,
      object: target_object
    )

    # ActivityPub Activity記録も作成
    target_object.activities.create!(
      actor: @sender,
      activity_type: 'Announce',
      ap_id: @activity['id'],
      published_at: Time.current,
      local: false,
      processed: true
    )

    Rails.logger.info "📢 Announce created: #{reblog.id}, reblogs_count updated to #{target_object.reload.reblogs_count}"
  end

  def extract_like_object_id
    object = @activity['object']
    object.is_a?(Hash) ? object['id'] : object
  end

  def find_target_object(object_ap_id)
    target_object = ActivityPubObject.find_by(ap_id: object_ap_id)

    Rails.logger.warn "⚠️ Target object not found for Like: #{object_ap_id}" unless target_object

    target_object
  end

  def create_or_update_like(target_object)
    # 既存のLikeをチェック
    existing_like = target_object.activities.find_by(
      actor: @sender,
      activity_type: 'Like'
    )

    if existing_like
      Rails.logger.info "❤️ Like already exists: #{existing_like.id}"
      return
    end

    # 新しいLikeを作成
    like = target_object.activities.create!(
      actor: @sender,
      activity_type: 'Like',
      ap_id: @activity['id'],
      published_at: Time.current,
      local: false,
      processed: true
    )

    # お気に入り数を更新
    target_object.increment!(:favourites_count)

    Rails.logger.info "❤️ Like created: #{like.id}, favourites_count updated to #{target_object.favourites_count}"
  end
end
