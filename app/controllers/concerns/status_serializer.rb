# frozen_string_literal: true

module StatusSerializer
  extend ActiveSupport::Concern
  include TextLinkingHelper

  private

  def parse_content_links_only(content)
    return content if content.blank?

    # API用: 絵文字HTMLがあればショートコードに戻す
    # クライアント側でemojis配列を使って絵文字処理
    convert_emoji_html_to_shortcode(content)
  end

  def parse_content_for_frontend(content)
    return '' if content.blank?

    # 既にHTMLリンクが含まれている場合（外部投稿）はサニタイズ + 絵文字処理
    if content.include?('<a ') || content.include?('<p>')
      # 外部投稿: まずサニタイズしてから絵文字処理
      sanitized = sanitize_html_for_display(content)
      if sanitized.include?('<img') && sanitized.include?('custom-emoji')
        sanitized
      else
        EmojiPresenter.present_with_emojis(sanitized)
      end
    else
      # ローカル投稿: 絵文字処理 + URLリンク化
      emoji_processed_content = if content.include?('<img') && content.include?('custom-emoji')
                                  content
                                else
                                  EmojiPresenter.present_with_emojis(content)
                                end

      auto_link_urls(emoji_processed_content)
    end
  end

  def serialized_emojis(status)
    # 防御的プログラミング: 常に配列を返し、nullは返さない
    return [] if status.nil? || status.content.blank?

    emojis = if defined?(@emoji_cache) && @emoji_cache
               resolve_emojis_from_cache(status)
             else
               domain = status.actor&.domain
               EmojiPresenter.extract_emojis_from(status.content, domain: domain)
             end

    result = emojis.filter_map(&:to_activitypub)
    result.is_a?(Array) ? result : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize emojis for status #{status&.id}: #{e.message}"
    [] # エラー時は常に空配列を返す
  end

  def resolve_emojis_from_cache(status)
    shortcodes = EmojiPresenter.extract_shortcodes_from(status.content)
    domain = status.actor&.domain

    shortcodes.filter_map do |code|
      @emoji_cache[:local][code] ||
        @emoji_cache[:remote]["#{code}:#{domain}"] ||
        @emoji_cache[:remote]["#{code}:"]
    end.uniq(&:shortcode)
  end
end
