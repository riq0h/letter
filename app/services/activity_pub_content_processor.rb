# frozen_string_literal: true

class ActivityPubContentProcessor
  include TextLinkingHelper

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

    if content.include?('<') && content.include?('>')
      normalized_content = normalize_html_structure(content)
      linked_content = apply_url_links_to_html(normalized_content)
      mention_linked_content = apply_mention_links_to_html(linked_content)
    else
      escaped_text = ERB::Util.html_escape(ActionView::Base.full_sanitizer.sanitize(content).strip).gsub("\n", '<br>')
      linked_content = apply_url_links(escaped_text)
      mention_linked_content = apply_mention_links(linked_content)
    end
    # ActivityPub標準に従ってpタグで囲む
    wrapped_content = wrap_content_in_p(mention_linked_content)
    object.update_column(:content, wrapped_content) if wrapped_content != content

    # リモート投稿の場合はActivityPubメタデータからも処理
    process_activitypub_metadata unless object.local?
  end

  def public_url
    if object.ap_id.present? && !object.local?
      # bsky.brid.gyの場合はBlueskyの実際のURLに変換
      return convert_bsky_bridge_url(object.ap_id) if object.ap_id.include?('bsky.brid.gy')

      return object.ap_id
    end

    return nil unless object.actor&.username

    # クライアント向けにはAPI形式のURLを返す（ブラウザアクセス時はコントローラでリダイレクト）
    base_url = Rails.application.config.activitypub.base_url
    "#{base_url}/users/#{object.actor.username}/posts/#{object.id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to generate public_url for object #{object.id}: #{e.message}"
    object.ap_id.presence || ''
  end

  private

  attr_reader :object

  def convert_bsky_bridge_url(bridge_url)
    # bsky.brid.gyのブリッジURLを実際のBlueskyURLに変換
    post_id = extract_bluesky_post_id(bridge_url)
    return bridge_url unless post_id

    # ActorからBlueskyハンドルを取得
    bluesky_handle = extract_bluesky_handle_from_actor
    return bridge_url unless bluesky_handle

    # BlueskyのURLを構築
    "https://bsky.app/profile/#{bluesky_handle}/post/#{post_id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to convert bsky.brid.gy URL #{bridge_url}: #{e.message}"
    bridge_url
  end

  def extract_bluesky_post_id(bridge_url)
    # URLの最後の部分（post ID）を抽出
    match = bridge_url.match(/\/app\.bsky\.feed\.post\/([^\/?#]+)/)
    match&.[](1)
  end

  def extract_bluesky_handle_from_actor
    # bsky.brid.gyのActorからBlueskyハンドルを取得
    actor = object.actor
    return nil unless actor

    # まずusernameを試す
    username = actor.username
    if username&.exclude?('did:plc:')
      # usernameがDID形式でない場合は、それをBlueskyハンドルとして使用
      return username
    end

    # preferredUsernameがあれば使用
    return actor.preferred_username if actor.respond_to?(:preferred_username) && actor.preferred_username.present?

    nil
  end

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
      next if excluded_from_preview?(url)

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

  def excluded_from_preview?(url)
    # プレビューリンク生成から除外するドメインリスト
    excluded_domains = [
      'bsky.app',
      'bsky.social',
      'bsky.brid.gy'
    ]

    uri = URI.parse(url)
    excluded_domains.any? { |domain| uri.host&.include?(domain) }
  rescue URI::InvalidURIError
    false
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

  def process_activitypub_metadata
    # リモート投稿のActivityPubメタデータからmentions/tagsを処理
    Rails.logger.debug { "Processing ActivityPub metadata for remote object #{object.id}" }

    # ActivityPubのtagフィールドから処理する必要がある場合はここで実装
    # 現在はテキストベースの処理のみを有効化
    Rails.logger.debug { "ActivityPub metadata processing enabled for object #{object.id}" }
  end

  def normalize_html_structure(content)
    return content if content.blank?

    content.gsub('<p><div>', '<div>')
           .gsub('</div></p>', '</div>')
           .gsub('<p></p>', '')
  end

  def wrap_content_in_p(content)
    return content if content.blank?

    trimmed_content = content.strip

    # 既にpタグで囲まれている場合はそのまま返す
    return content if trimmed_content.start_with?('<p') && trimmed_content.end_with?('</p>')

    # ブロック要素で始まる場合は pタグで囲まない
    block_elements = %w[<div <article <section <aside <nav <main <header <footer <figure <blockquote <ul <ol <dl <table <form]
    return content if block_elements.any? { |element| trimmed_content.start_with?(element) }

    "<p>#{content}</p>"
  end
end
