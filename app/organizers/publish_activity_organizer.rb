# frozen_string_literal: true

# Activityの作成と配信を管理するOrganizer
# 複数のステップ（Activity作成、配信先決定、ジョブ投入）を統括
class PublishActivityOrganizer
  include ActivityDeliveryHelper

  class Result < OrganizerResult
    attr_reader :activity

    def initialize(success:, activity: nil, error: nil)
      @activity = activity
      super(success: success, error: error)
    end
  end

  def self.call(actor, activity_type:, object: nil, target_ap_id: nil, **)
    new(actor, activity_type: activity_type, object: object, target_ap_id: target_ap_id, **).call
  end

  def initialize(actor, activity_type:, object: nil, target_ap_id: nil, **options)
    @actor = actor
    @activity_type = activity_type
    @object = object
    @target_ap_id = target_ap_id
    @options = options
  end

  # Activityを作成して配信処理を実行
  def call
    Rails.logger.info "📤 Creating #{@activity_type} activity for #{@actor.username}"

    # 特定のActivity種別に応じた処理
    case @activity_type
    when 'Create'
      handle_create_activity
    when 'Follow'
      handle_follow_activity
    when 'Announce'
      handle_announce_activity
    when 'Like'
      handle_like_activity
    when 'Undo'
      handle_undo_activity
    when 'Delete'
      handle_delete_activity
    else
      failure("Unsupported activity type: #{@activity_type}")
    end
  rescue StandardError => e
    Rails.logger.error "❌ Failed to publish activity: #{e.message}"
    failure(e.message)
  end

  private

  attr_reader :actor, :activity_type, :object, :target_ap_id, :options

  def success(activity)
    Result.new(success: true, activity: activity)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  # Create Activity（投稿作成）の処理
  def handle_create_activity
    # オブジェクトがない場合は新規作成
    @object ||= create_note_object

    activity = create_activity
    # ActivityPubObjectが自動で配信するため、ここでは配信しない

    Rails.logger.info "✅ Create activity #{activity.id} published"
    success(activity)
  end

  # Follow Activityの処理
  def handle_follow_activity
    return failure('Target AP ID required for Follow activity') unless @target_ap_id

    activity = create_activity
    deliver_to_target(activity)

    Rails.logger.info "✅ Follow activity #{activity.id} published"
    success(activity)
  end

  # Announce Activity（ブースト）の処理
  def handle_announce_activity
    return failure('Target AP ID required for Announce activity') unless @target_ap_id

    activity = create_activity
    deliver_activity(activity)

    Rails.logger.info "✅ Announce activity #{activity.id} published"
    success(activity)
  end

  # Like Activity（いいね）の処理
  def handle_like_activity
    return failure('Target AP ID required for Like activity') unless @target_ap_id

    activity = create_activity
    deliver_to_target(activity) if @target_ap_id.present?

    Rails.logger.info "✅ Like activity #{activity.id} published"
    success(activity)
  end

  # Undo Activityの処理
  def handle_undo_activity
    return failure('Target AP ID required for Undo activity') unless @target_ap_id

    activity = create_activity
    deliver_activity(activity)

    Rails.logger.info "✅ Undo activity #{activity.id} published"
    success(activity)
  end

  # Delete Activityの処理
  def handle_delete_activity
    return failure('Target AP ID required for Delete activity') unless @target_ap_id

    activity = create_activity
    deliver_activity(activity)

    Rails.logger.info "✅ Delete activity #{activity.id} published"
    success(activity)
  end

  # Activity作成の共通処理
  def create_activity
    Activity.create!(
      ap_id: generate_activity_id,
      activity_type: @activity_type,
      actor: @actor,
      object: @object,
      target_ap_id: @target_ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )
  end

  # Activity IDの生成
  def generate_activity_id
    ApIdGeneration.generate_ap_id
  end

  # 新規Noteオブジェクトの作成
  def create_note_object
    content = @options[:content] || ''
    visibility = @options[:visibility] || 'public'

    ActivityPubObject.create!(
      ap_id: generate_object_id,
      object_type: 'Note',
      actor: @actor,
      content: content,
      visibility: visibility,
      published_at: Time.current,
      local: true,
      sensitive: @options[:sensitive] || false,
      summary: @options[:summary],
      in_reply_to_ap_id: @options[:in_reply_to_ap_id],
      conversation_ap_id: @options[:conversation_ap_id]
    )
  end

  # オブジェクトIDの生成
  def generate_object_id
    object_id = Letter::Snowflake.generate
    "#{@actor.ap_id}/posts/#{object_id}"
  end

  # Activity配信の処理（フォロワーと特定ターゲット）
  def deliver_activity(activity)
    # フォロワーへの配信
    deliver_to_followers(activity) if should_deliver_to_followers?

    # 特定ターゲットへの配信
    deliver_to_target(activity) if @target_ap_id.present?
  end

  # フォロワーへの配信が必要かチェック
  def should_deliver_to_followers?
    %w[Create Announce Delete Undo].include?(@activity_type)
  end

  # フォロワーへの配信処理
  def deliver_to_followers(activity)
    inbox_urls = collect_follower_inboxes
    return if inbox_urls.empty?

    Rails.logger.info "📬 Queuing delivery to #{inbox_urls.count} follower inboxes"
    enqueue_send_activity(activity, inbox_urls)
  end

  # 特定ターゲットへの配信処理
  def deliver_to_target(activity)
    target_actor = find_target_actor
    return unless target_actor&.inbox_url

    Rails.logger.info "📬 Queuing delivery to target: #{target_actor.inbox_url}"
    enqueue_send_activity(activity, [target_actor.inbox_url])
  end

  # フォロワーのInbox URL収集
  def collect_follower_inboxes
    followers = @actor.followers.where(local: false)
    inbox_urls = followers.filter_map(&:inbox_url).uniq

    # shared_inbox_urlがある場合は優先使用
    shared_inboxes = followers.filter_map(&:shared_inbox_url).uniq

    # 重複を除去してshared_inboxを優先
    optimize_inbox_urls(shared_inboxes, inbox_urls)
  end

  # Inbox URLの最適化（shared_inboxを優先）
  def optimize_inbox_urls(shared_inboxes, inbox_urls)
    shared_domains = shared_inboxes.filter_map do |url|
      URI(url).host
    rescue URI::InvalidURIError => e
      Rails.logger.warn "Invalid shared inbox URL: #{url} - #{e.message}"
      nil
    end

    individual_inboxes = inbox_urls.reject do |inbox_url|
      shared_domains.include?(URI(inbox_url).host)
    rescue URI::InvalidURIError => e
      Rails.logger.warn "Invalid inbox URL: #{inbox_url} - #{e.message}"
      false
    end

    shared_inboxes + individual_inboxes
  end

  # ターゲットアクターの検索・取得
  def find_target_actor
    return nil unless @target_ap_id

    # ローカルアクターから検索
    Actor.find_by(ap_id: @target_ap_id) ||
      # リモートアクターを取得
      ActorFetcher.new.fetch_and_create(@target_ap_id)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to find target actor #{@target_ap_id}: #{e.message}"
    nil
  end
end
