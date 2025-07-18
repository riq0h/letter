# frozen_string_literal: true

class ActivityPubContentProcessor
  def initialize(object)
    @object = object
  end

  def display_content
    return content_plaintext if content.blank?
    return content_plaintext unless sensitive?

    summary.presence || 'Sensitive content'
  end

  def content_plaintext
    return '' if content.blank?

    # HTMLタグを除去してプレーンテキストを取得
    ActionController::Base.helpers.strip_tags(content)
  end

  def process_text_content
    return if content.blank?

    # テキスト内容の処理を実行
    extract_mentions
    extract_hashtags
    process_links
  end

  def public_url
    return object.ap_id if object.ap_id.present? && !object.local?
    return nil unless object.actor&.username

    # base_urlから適切なURLを生成
    base_url = Rails.application.config.activitypub.base_url
    "#{base_url}/@#{object.actor.username}/#{object.id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to generate public_url for object #{object.id}: #{e.message}"
    object.ap_id.presence || ''
  end

  private

  attr_reader :object

  delegate :content, :summary, :sensitive?, to: :object

  def extract_mentions
    # メンション抽出ロジック
    return unless content.include?('@')

    mention_pattern = /@([a-zA-Z0-9_]+)(?:@([a-zA-Z0-9.-]+))?/
    content.scan(mention_pattern) do |username, domain|
      create_mention(username, domain)
    end
  end

  def extract_hashtags
    # ハッシュタグ抽出ロジック
    return unless content.include?('#')

    hashtag_pattern = /#([a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]+)/
    content.scan(hashtag_pattern) do |tag_name|
      create_hashtag(tag_name.first)
    end
  end

  def process_links
    urls = extract_urls_from_content(object.content)
    return if urls.empty?

    urls.each do |url|
      existing_preview = LinkPreview.find_by(url: url)
      next if existing_preview

      FetchLinkPreviewJob.perform_later(url, object.id)
    end
  end

  def extract_urls_from_content(content)
    return [] if content.blank?

    doc = Nokogiri::HTML.fragment(content)
    doc.css('a[href]').pluck('href').grep(/\Ahttps?:\/\//).uniq
  end

  def create_mention(username, domain)
    # メンション作成処理
    target_actor = find_actor(username, domain)
    return unless target_actor

    object.mentions.find_or_create_by(actor: target_actor)
  end

  def create_hashtag(tag_name)
    # ハッシュタグ作成処理
    tag = Tag.find_or_create_by(name: tag_name.downcase)
    object.object_tags.find_or_create_by(tag: tag)
  end

  def find_actor(username, domain)
    if domain
      Actor.find_by(username: username, domain: domain)
    else
      Actor.find_by(username: username, local: true)
    end
  end
end
