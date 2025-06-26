# frozen_string_literal: true

require_relative '../../services/html_stripper'

module ActivityPubCreateHandlers
  extend ActiveSupport::Concern
  include ActivityPubVisibilityHelper
  include ActivityPubMediaHandler
  include ActivityPubConversationHandler
  include ActivityPubUtilityHelpers

  private

  def handle_create_activity
    Rails.logger.info '📝 Processing Create activity'

    object_data = @activity['object']

    unless valid_create_object?(object_data)
      Rails.logger.warn '⚠️ Invalid object in Create activity'
      head :accepted
      return
    end

    return handle_existing_object(object_data) if object_exists?(object_data)

    create_new_object(object_data)
  end

  def valid_create_object?(object_data)
    object_data.is_a?(Hash)
  end

  def object_exists?(object_data)
    ActivityPubObject.find_by(ap_id: object_data['id'])
  end

  def handle_existing_object(object_data)
    Rails.logger.warn "⚠️ Object already exists: #{object_data['id']}"
    head :accepted
  end

  def create_new_object(object_data)
    object = ActivityPubObject.create!(build_object_attributes(object_data))

    handle_media_attachments(object, object_data)
    handle_mentions(object, object_data)
    handle_emojis(object, object_data)
    handle_poll(object, object_data) if object_data['type'] == 'Question' || object_data['oneOf'] || object_data['anyOf']
    handle_vote(object, object_data) if object_data['type'] == 'Vote'
    handle_direct_message_conversation(object, object_data) if object.visibility == 'direct'
    update_reply_count_if_needed(object)

    # アクティビティベースでpin投稿を更新
    update_pin_posts_if_needed(object.actor)

    Rails.logger.info "📝 Object created: #{object.id}"
    head :accepted
  end

  def build_object_attributes(object_data)
    attributes = {
      ap_id: object_data['id'],
      actor: @sender,
      object_type: object_data['type'] || 'Note',
      content: object_data['content'],
      content_plaintext: ActivityPub::HtmlStripper.strip(object_data['content']),
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

    # 最後にpin投稿を更新してから24時間経過している場合のみ更新
    last_pin_update = actor.pinned_statuses.maximum(:updated_at)
    return if last_pin_update && last_pin_update > 24.hours.ago

    Rails.logger.info "🔄 Updating pin posts for #{actor.username}@#{actor.domain} (activity-based)"

    # 既存のpin投稿を削除して再取得
    actor.pinned_statuses.destroy_all

    # バックグラウンドで実行して応答時間に影響しないようにする
    UpdatePinPostsJob.perform_later(actor.id)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to trigger pin posts update for #{actor.username}@#{actor.domain}: #{e.message}"
  end

  def handle_poll(object, object_data)
    poll_options = object_data['oneOf'] || object_data['anyOf']
    return if poll_options.blank?

    options = poll_options.map { |option| { 'title' => option['name'] } }

    expires_at = if object_data['endTime'].present?
                   Time.zone.parse(object_data['endTime'])
                 else
                   1.day.from_now
                 end

    Poll.create!(
      object: object,
      options: options,
      expires_at: expires_at,
      multiple: object_data['anyOf'].present?,
      hide_totals: false,
      votes_count: 0,
      voters_count: object_data['votersCount'] || 0
    )

    Rails.logger.info "📊 Poll created with #{options.count} options for object #{object.id}"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create poll: #{e.message}"
  end

  def handle_vote(object, object_data)
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

    # 投票を記録
    target_object.poll.vote_for!(object.actor, [choice_index])

    Rails.logger.info "🗳️ Vote recorded: #{object.actor.username} voted '#{choice_name}' on poll #{target_object.poll.id}"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to process vote: #{e.message}"
  end
end
