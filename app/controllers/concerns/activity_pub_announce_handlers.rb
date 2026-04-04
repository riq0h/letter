# frozen_string_literal: true

module ActivityPubAnnounceHandlers
  extend ActiveSupport::Concern
  include ActivityPubHelper

  private

  # Announce Activity処理（ブースト）
  def handle_announce_activity
    Rails.logger.info '📢 Processing Announce activity'

    object_ap_id = extract_announce_object_id
    return head(:accepted) unless object_ap_id

    target_object = find_local_target_object(object_ap_id)

    if target_object
      # ローカルに存在するオブジェクトへのAnnounce
      create_or_update_announce(target_object)
    elsif followed_sender?
      # フォロー中アクターが他人の投稿をリブログ → 軽量処理（タイムライン表示用）
      handle_followed_actor_reblog(object_ap_id)
    else
      Rails.logger.debug { "📢 Skipping Announce from non-followed actor: #{object_ap_id}" }
    end

    head :accepted
  end

  def extract_announce_object_id
    extract_activity_object_id(@activity['object'])
  end

  def create_or_update_announce(target_object)
    if target_object.actor.local?
      # 自分の投稿へのAnnounce → フル処理（通知+Activityレコード+フィード）
      return if announce_already_exists?(target_object)

      create_new_announce(target_object)
    elsif followed_sender?
      # フォロー中アクターによる他人の投稿のAnnounce → 軽量処理
      create_lightweight_reblog(target_object)
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

  # フォロー中アクターのリブログを軽量に処理（通知・Activityレコードなし）
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
    Rails.logger.debug { '📢 Lightweight reblog already exists' }
  end

  # フォロー中アクターが他人の投稿をリブログ（ターゲットがローカルにない場合）
  def handle_followed_actor_reblog(object_ap_id)
    # リモートからオブジェクトを取得
    target_object = fetch_and_create_remote_object(object_ap_id)
    return unless target_object

    create_lightweight_reblog(target_object)
  rescue StandardError => e
    Rails.logger.warn "📢 Failed to process followed actor reblog: #{e.message}"
  end

  def fetch_and_create_remote_object(ap_id)
    resolver = Search::RemoteResolverService.new
    resolver.resolve_remote_status(ap_id)
  end

  def followed_sender?
    @followed_sender ||= HomeFeedManager.followed_actor_ids.include?(@sender.id)
  end

  def find_local_target_object(object_ap_id)
    ActivityPubObject.find_by(ap_id: object_ap_id)
  end
end
