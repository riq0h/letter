# frozen_string_literal: true

module MentionProcessor
  extend ActiveSupport::Concern

  private

  def process_mentions_and_tags
    return if @status.content.blank?

    process_mentions
    process_hashtags
  end

  def process_mentions
    return if @mentions.blank?

    if @mentions.is_a?(Array)
      process_explicit_mentions(@mentions)
    else
      extract_and_process_mentions
    end
  end

  def process_explicit_mentions(mentions_param)
    mentions_param.each do |username|
      mentioned_actor = Actor.find_by(username: username.delete('@'))
      create_mention_for(mentioned_actor) if mentioned_actor && mentioned_actor != current_user
    end
  end

  def extract_and_process_mentions
    mentioned_usernames = extract_mentioned_usernames(@status.content)
    mentioned_usernames.each do |username|
      mentioned_actor = Actor.find_by(username: username)
      create_mention_for(mentioned_actor) if mentioned_actor && mentioned_actor != current_user
    end
  end

  def extract_mentioned_usernames(content)
    content.scan(/@([[:word:]]+)/).flatten.uniq
  end

  def create_mention_for(actor)
    Mention.find_or_create_by(object: @status, actor: actor)
  end

  def process_hashtags
    tag_names = extract_hashtag_names(@status.content)
    tag_names.each do |tag_name|
      tag = Tag.find_or_create_by(name: tag_name.downcase)
      ObjectTag.find_or_create_by(object: @status, tag: tag)
    end
  end

  def extract_hashtag_names(content)
    content.scan(/#([[:word:]]+)/).flatten.uniq
  end

  def convert_mentions_to_html_links
    return if @status.content.blank?
    return if @status.content.include?('<a ') # 既にHTMLリンクが含まれている場合はスキップ

    # プレーンテキストの場合のみリンク化処理
    # 1. URLをHTMLリンクに変換
    updated_content = apply_url_links(@status.content)

    # 2. メンションをHTMLリンクに変換
    # @usernameパターンをリンクに変換（Actor存在チェック付き）
    updated_content = apply_mention_links_to_html(updated_content)

    # 絵文字はショートコードのままで保存（Mastodon API標準に準拠）
    # フロントエンド表示時とemojis配列で適切に処理

    @status.update!(content: updated_content) if updated_content != @status.content
  end

  def apply_url_links(content)
    # URLパターンを検出してリンク化
    url_pattern = /https?:\/\/[^\s<>\u0022]+(?:[.,!?:](?=[^\s<>\u0022])|[^\s<>\u0022.,!?:])*/
    content.gsub(url_pattern) do |url|
      escaped_url = CGI.escapeHTML(url)
      %(<a href="#{escaped_url}" target="_blank" rel="nofollow noopener noreferrer">#{escaped_url}</a>)
    end
  end

  def apply_mention_links_to_html(content)
    # @username形式のメンションをHTMLリンクに変換
    content.gsub(/@([[:word:]]+)/) do |match|
      username = ::Regexp.last_match(1)
      mentioned_user = Actor.find_by(username: username)

      if mentioned_user
        escaped_username = CGI.escapeHTML(username)
        profile_url = "#{Rails.application.config.activitypub.base_url}/users/#{escaped_username}"
        %(<a href="#{profile_url}" class="mention" data-user-id="#{mentioned_user.id}">@#{escaped_username}</a>)
      else
        match # ユーザが見つからない場合は元のテキストを保持
      end
    end
  end
end
