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

    result = if defined?(@emoji_cache) && @emoji_cache
               resolve_emojis_from_cache(status)
             else
               resolve_emojis_without_cache(status)
             end

    result.is_a?(Array) ? result : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize emojis for status #{status&.id}: #{e.message}"
    [] # エラー時は常に空配列を返す
  end

  # emojis配列を構築する。DB保存値はdowncaseなのでURL解決はdowncaseキーで行い、
  # 出力するshortcodeは本文の表記(大文字小文字)をそのまま用いる。こうしないと
  # クライアントが本文の :ShortCode: と emojis配列を照合できず絵文字化されない。
  def resolve_emojis_from_cache(status)
    domain = status.actor&.domain

    emojis_for_tokens(status.content) do |key|
      @emoji_cache[:local][key] ||
        @emoji_cache[:remote]["#{key}:#{domain}"] ||
        @emoji_cache[:remote]["#{key}:"]
    end
  end

  def resolve_emojis_without_cache(status)
    domain = status.actor&.domain
    records = EmojiPresenter.extract_emojis_from(status.content, domain: domain)
    return [] if records.empty?

    by_code = records.index_by(&:shortcode) # 保存値(downcase)キー
    emojis_for_tokens(status.content) { |key| by_code[key] }
  end

  # 本文の表記そのままのトークンごとに絵文字レコードを解決し、
  # 出力shortcodeを本文表記に差し替えたActivityPub表現を返す
  def emojis_for_tokens(content)
    seen = Set.new
    EmojiPresenter.extract_raw_shortcodes_from(content).filter_map do |token|
      emoji = yield(token.downcase)
      next unless emoji
      next unless seen.add?(token)

      emoji.to_activitypub.merge(shortcode: token)
    end
  end
end
