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

    # 投稿者のドメインを渡して、同一ドメインの絵文字を優先検索
    domain = status.actor&.domain
    emojis = EmojiPresenter.extract_emojis_from(status.content, domain: domain)
    result = emojis.filter_map(&:to_activitypub) # nil エントリを除去

    # 常に配列であることを保証
    result.is_a?(Array) ? result : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize emojis for status #{status&.id}: #{e.message}"
    Rails.logger.warn "Backtrace: #{e.backtrace.first(3).join(', ')}"
    [] # エラー時は常に空配列を返す
  end
end
