# frozen_string_literal: true

# ActivityPubのCreateアクティビティ処理を統括するOrganizer
class CreateActivityOrganizer
  include ActivityPubVisibilityHelper
  include ActivityPubMediaHandler
  include ActivityPubConversationHandler
  include ActivityPubUtilityHelpers

  class Result
    attr_reader :success, :object, :error

    def initialize(success:, object: nil, error: nil)
      @success = success
      @object = object
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

  def self.call(activity, sender, preserve_relay_info: nil)
    new(activity, sender, preserve_relay_info: preserve_relay_info).call
  end

  def initialize(activity, sender, preserve_relay_info: nil)
    @activity = activity
    @sender = sender
    @preserve_relay_info = preserve_relay_info
  end

  # Create アクティビティを処理
  def call
    Rails.logger.info '📝 Processing Create activity'

    object_data = @activity['object']

    return failure('Invalid object in Create activity') unless valid_create_object?(object_data)
    return success(nil) if handle_existing_object?(object_data)

    # Voteオブジェクトは特別処理
    if vote_object?(object_data)
      handle_vote_activity_only(object_data)
      return success(nil)
    end

    # 新しいオブジェクトを作成
    object = create_new_object(object_data)
    return failure('Failed to create object') unless object

    # 関連データの処理
    process_object_associations(object, object_data)
    update_related_data(object)

    Rails.logger.info "📝 Object created: #{object.id}"
    success(object)
  rescue StandardError => e
    Rails.logger.error "Create activity processing failed: #{e.message}"
    failure(e.message)
  end

  private

  attr_reader :activity, :sender, :preserve_relay_info

  def success(object)
    Result.new(success: true, object: object)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  def valid_create_object?(object_data)
    object_data.is_a?(Hash)
  end

  def handle_existing_object?(object_data)
    if ActivityPubObject.find_by(ap_id: object_data['id'])
      Rails.logger.warn "⚠️ Object already exists: #{object_data['id']}"
      true
    else
      false
    end
  end

  def vote_object?(object_data)
    object_data['type'] == 'Vote'
  end

  def create_new_object(object_data)
    ActivityPubObject.create!(build_object_attributes(object_data))
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create object: #{e.message}"
    nil
  end

  def build_object_attributes(object_data)
    attributes = {
      ap_id: object_data['id'],
      actor: @sender,
      object_type: object_data['type'] || 'Note',
      content: object_data['content'] || '',
      content_plaintext: ActivityPub::HtmlStripper.strip(object_data['content'] || ''),
      summary: object_data['summary'],
      url: object_data['url'],
      in_reply_to_ap_id: object_data['inReplyTo'],
      conversation_ap_id: object_data['conversation'],
      published_at: parse_published_date(object_data['published']),
      sensitive: object_data['sensitive'] || false,
      visibility: determine_visibility(object_data),
      raw_data: object_data.to_json,
      local: false
    }

    # リレー経由の投稿の場合はrelay_idを設定
    attributes[:relay_id] = @preserve_relay_info.id if @preserve_relay_info

    attributes
  end

  def process_object_associations(object, object_data)
    handle_media_attachments(object, object_data)
    handle_mentions(object, object_data)
    handle_emojis(object, object_data)
    handle_poll(object, object_data) if poll_object?(object_data)
    handle_quote_post(object, object_data) if quote_post_object?(object_data)
    handle_direct_message_conversation(object, object_data) if object.visibility == 'direct'
  end

  def update_related_data(object)
    update_reply_count_if_needed(object)
    update_pin_posts_if_needed(object.actor)
  end

  def poll_object?(object_data)
    result = object_data['type'] == 'Question' || object_data['oneOf'] || object_data['anyOf']
    Rails.logger.debug do
      "poll_object? check: type=#{object_data['type']}, " \
        "oneOf=#{object_data['oneOf']}, anyOf=#{object_data['anyOf']}, result=#{result}"
    end
    result
  end

  def quote_post_object?(object_data)
    object_data['quoteUrl'] || object_data['_misskey_quote'] || object_data['quoteUri']
  end

  def handle_mentions(object, object_data)
    tags = Array(object_data['tag'])
    mention_tags = tags.select { |tag| tag['type'] == 'Mention' }

    mention_tags.each do |mention_tag|
      href = mention_tag['href']
      next unless href

      # ローカルアクターかチェック
      mentioned_actor = Actor.find_by(ap_id: href)
      next unless mentioned_actor&.local?

      # Mentionレコード作成
      Mention.create!(
        object: object,
        actor: mentioned_actor,
        ap_id: "#{object.ap_id}#mention-#{mentioned_actor.id}"
      )

      Rails.logger.info "💬 Mention created: #{mentioned_actor.username}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to handle mentions: #{e.message}"
  end

  def handle_emojis(object, object_data)
    tags = Array(object_data['tag'])
    emoji_tags = tags.select { |tag| tag['type'] == 'Emoji' }

    emoji_tags.each do |emoji_tag|
      shortcode = emoji_tag['name']&.gsub(/^:|:$/, '')
      icon_url = emoji_tag.dig('icon', 'url')

      next unless shortcode.present? && icon_url.present?

      remote_domain = extract_domain_from_uri(object.ap_id)
      next unless remote_domain

      existing_emoji = CustomEmoji.find_by(shortcode: shortcode, domain: remote_domain)
      next if existing_emoji

      CustomEmoji.create!(
        shortcode: shortcode,
        domain: remote_domain,
        image_url: icon_url,
        visible_in_picker: false,
        disabled: false
      )

      Rails.logger.info "🎨 Remote emoji created: :#{shortcode}: from #{remote_domain}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to handle emojis: #{e.message}"
  end

  def extract_domain_from_uri(uri)
    return nil unless uri

    parsed_uri = URI.parse(uri)
    parsed_uri.host
  rescue URI::InvalidURIError
    nil
  end

  def update_reply_count_if_needed(object)
    return unless object.in_reply_to_ap_id

    parent_object = ActivityPubObject.find_by(ap_id: object.in_reply_to_ap_id)
    return unless parent_object

    parent_object.increment!(:replies_count)
    Rails.logger.info "💬 Reply count updated for #{parent_object.ap_id}: #{parent_object.replies_count}"
  end

  def update_pin_posts_if_needed(actor)
    return unless actor && !actor.local? && actor.featured_url.present?

    # Solid Cache ベースの重複防止（競合状態対策）
    cache_key = "pin_posts_job:#{actor.id}"
    return if Rails.cache.read(cache_key)

    # 最後にpin投稿を更新してから24時間経過している場合のみ更新
    last_pin_update = actor.pinned_statuses.maximum(:updated_at)
    if last_pin_update.nil?
      # Pin投稿が一度も更新されていない場合は最後のオブジェクト作成から6時間制限
      last_activity = actor.objects.maximum(:created_at)
      return if last_activity && last_activity < 6.hours.ago
    elsif last_pin_update > 24.hours.ago
      return
    end

    # 既に実行待ちのジョブがある場合は重複を避ける
    existing_jobs = SolidQueue::Job.where(class_name: 'UpdatePinPostsJob')
                                   .where('created_at > ?', 1.hour.ago)
                                   .select do |job|
      job_args = job.arguments.is_a?(Hash) ? job.arguments['arguments'] : job.arguments
      job_args.is_a?(Array) && job_args.first == actor.id
    end

    return if existing_jobs.any?

    # キャッシュに記録（1時間）
    Rails.cache.write(cache_key, true, expires_in: 1.hour)

    Rails.logger.info "🔄 Updating pin posts for #{actor.username}@#{actor.domain} (activity-based)"
    UpdatePinPostsJob.perform_later(actor.id)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to trigger pin posts update for #{actor.username}@#{actor.domain}: #{e.message}"
  end

  def handle_poll(object, object_data)
    Rails.logger.debug { "handle_poll called with object_data: #{object_data.inspect}" }
    poll_options = object_data['oneOf'] || object_data['anyOf']
    Rails.logger.debug { "poll_options: #{poll_options.inspect}" }
    return if poll_options.blank?

    options = poll_options.map { |option| { 'title' => option['name'] } }

    expires_at = if object_data['endTime'].present?
                   Time.zone.parse(object_data['endTime'])
                 else
                   1.day.from_now
                 end

    poll = Poll.create!(
      object: object,
      options: options,
      expires_at: expires_at,
      multiple: object_data['anyOf'].present?,
      hide_totals: false,
      votes_count: 0,
      voters_count: object_data['votersCount'] || 0
    )

    schedule_poll_expiration_job(poll)

    Rails.logger.info "📊 Poll created with #{options.count} options for object #{object.id}, poll ID: #{poll.id}"
    poll
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create poll: #{e.message}"
    Rails.logger.error "Poll creation stacktrace: #{e.backtrace.join("\n")}"
    raise
  end

  def handle_vote_activity_only(object_data)
    # 投票オブジェクトは通常、inReplyToで投票対象を指している
    return if object_data['inReplyTo'].blank?

    # 投票対象の投稿を探す
    target_object = ActivityPubObject.find_by(ap_id: object_data['inReplyTo'])
    return unless target_object&.poll

    # 投票の選択肢を解析
    choice_name = object_data['name'] || object_data['content']
    return unless choice_name

    # 投票の選択肢インデックスを見つける
    choice_index = target_object.poll.option_titles.index(choice_name)
    return unless choice_index

    # 投票の選択肢を更新（レースコンディション対策のためトランザクション内でロック）
    Poll.transaction do
      poll = target_object.poll.lock!
      vote_counts = poll.vote_counts.dup
      vote_counts[choice_index] += 1
      poll.update!(vote_counts: vote_counts)
    end

    Rails.logger.info "🗳️ Vote processed for poll #{target_object.poll.id}: #{choice_name}"
  rescue StandardError => e
    Rails.logger.error "Failed to process vote: #{e.message}"
  end

  def schedule_poll_expiration_job(poll)
    return unless poll.expires_at

    PollExpirationNotifyJob.set(wait_until: poll.expires_at).perform_later(poll.id)
    Rails.logger.debug { "🗳️  Poll expiration job scheduled for #{poll.expires_at}" }
  rescue StandardError => e
    Rails.logger.error "Failed to schedule poll expiration job: #{e.message}"
  end

  def handle_quote_post(object, object_data)
    # 引用元のURLを取得（Misskey、Fedibird、その他の実装に対応）
    quoted_url = object_data['quoteUrl'] || object_data['_misskey_quote'] || object_data['quoteUri']
    return unless quoted_url

    # 引用元の投稿を検索
    quoted_object = ActivityPubObject.find_by(ap_id: quoted_url)
    return unless quoted_object

    # QuotePostレコードを作成
    quote_post = QuotePost.create!(
      actor: object.actor,
      object: object,
      quoted_object: quoted_object,
      shallow_quote: object.content.blank?,
      quote_text: object.content,
      visibility: object.visibility,
      ap_id: "#{object.ap_id}#quote"
    )

    Rails.logger.info "💬 Quote post created: #{quote_post.id} quotes #{quoted_object.ap_id}"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create quote post: #{e.message}"
  end
end
