# frozen_string_literal: true

# ステータスアクション（いいね・リブログ処理）を統括するOrganizer
# アクティビティ作成と配信を統合的に管理
class StatusActionOrganizer
  class Result
    attr_reader :success, :activity, :error

    def initialize(success:, activity: nil, error: nil)
      @success = success
      @activity = activity
      @error = error
      freeze
    end

    def success?
      success
    end

    def failure?
      !success
    end
  end

  def self.call(actor, action_type:, status:, original_activity: nil)
    new(actor, action_type: action_type, status: status, original_activity: original_activity).call
  end

  def initialize(actor, action_type:, status:, original_activity: nil)
    @actor = actor
    @action_type = action_type
    @status = status
    @original_activity = original_activity
  end

  # ステータスアクションを実行
  def call
    Rails.logger.info "📝 Processing status action #{@action_type} for status #{@status.id} by #{@actor.username}"

    case @action_type
    when 'like'
      create_like_activity
    when 'undo_like'
      create_undo_like_activity
    when 'announce'
      create_announce_activity
    when 'undo_announce'
      create_undo_announce_activity
    else
      failure("Unsupported action type: #{@action_type}")
    end
  rescue StandardError => e
    Rails.logger.error "❌ Failed to process status action: #{e.message}"
    failure(e.message)
  end

  private

  attr_reader :actor, :action_type, :status, :original_activity

  def success(activity)
    Result.new(success: true, activity: activity)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  # Likeアクティビティの作成処理
  def create_like_activity
    activity = Activity.create!(
      ap_id: generate_ap_id,
      activity_type: 'Like',
      actor: @actor,
      target_ap_id: @status.ap_id,
      object_ap_id: nil,
      published_at: Time.current,
      local: true
    )

    queue_activity_delivery(activity)
    Rails.logger.info "👍 Created Like activity #{activity.id} for status #{@status.id}"
    success(activity)
  end

  # Undo Likeアクティビティの作成処理
  def create_undo_like_activity
    like_activity = find_like_activity
    return failure('Like activity not found') unless like_activity

    undo_activity = Activity.create!(
      ap_id: generate_ap_id,
      activity_type: 'Undo',
      actor: @actor,
      target_ap_id: like_activity.ap_id,
      object_ap_id: nil,
      published_at: Time.current,
      local: true
    )

    # 元のLikeアクティビティを削除
    like_activity.destroy

    queue_activity_delivery(undo_activity)
    Rails.logger.info "🔄 Created Undo Like activity #{undo_activity.id} for status #{@status.id}"
    success(undo_activity)
  end

  # Announceアクティビティの作成処理
  def create_announce_activity
    activity = Activity.create!(
      ap_id: generate_ap_id,
      activity_type: 'Announce',
      actor: @actor,
      target_ap_id: @status.ap_id,
      object_ap_id: nil,
      published_at: Time.current,
      local: true
    )

    queue_activity_delivery(activity)
    Rails.logger.info "🔁 Created Announce activity #{activity.id} for status #{@status.id}"
    success(activity)
  end

  # Undo Announceアクティビティの作成処理
  def create_undo_announce_activity
    announce_activity = find_announce_activity
    return failure('Announce activity not found') unless announce_activity

    undo_activity = Activity.create!(
      ap_id: generate_ap_id,
      activity_type: 'Undo',
      actor: @actor,
      target_ap_id: announce_activity.ap_id,
      object_ap_id: nil,
      published_at: Time.current,
      local: true
    )

    # 元のAnnounceアクティビティを削除
    announce_activity.destroy

    queue_activity_delivery(undo_activity)
    Rails.logger.info "🔄 Created Undo Announce activity #{undo_activity.id} for status #{@status.id}"
    success(undo_activity)
  end

  # ActivityPub IDの生成
  def generate_ap_id
    "#{Rails.application.config.activitypub.base_url}/#{Letter::Snowflake.generate}"
  end

  # Likeアクティビティの検索
  def find_like_activity
    Activity.find_by(
      activity_type: 'Like',
      actor: @actor,
      target_ap_id: @status.ap_id
    )
  end

  # Announceアクティビティの検索
  def find_announce_activity
    Activity.find_by(
      activity_type: 'Announce',
      actor: @actor,
      target_ap_id: @status.ap_id
    )
  end

  # アクティビティ配信の実行
  def queue_activity_delivery(activity)
    target_inboxes = []

    # 投稿者が自分と異なり、ローカルでない場合のみ投稿者のinboxを追加
    target_inboxes << @status.actor.inbox_url if @status.actor != @actor && !@status.actor.local? && @status.actor.inbox_url.present?

    # フォロワーへの配信（Announce/Like共通）
    if activity.activity_type == 'Announce' && @status.visibility == 'public'
      follower_inboxes = @actor.followers.where(local: false).pluck(:inbox_url)
      target_inboxes.concat(follower_inboxes)
    end

    return if target_inboxes.empty?

    SendActivityJob.perform_later(activity.id, target_inboxes.uniq)
    Rails.logger.info "📤 Queued activity delivery for activity #{activity.id} to #{target_inboxes.uniq.count} inboxes"
  end
end
