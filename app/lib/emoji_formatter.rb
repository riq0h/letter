# frozen_string_literal: true

class EmojiFormatter
  include ActionView::Helpers::AssetTagHelper
  include Rails.application.routes.url_helpers

  attr_reader :html, :custom_emojis, :animate

  def initialize(html, custom_emojis: nil, animate: true)
    raise ArgumentError, 'HTML cannot be nil' if html.nil?

    @html = html
    @custom_emojis = custom_emojis || {}
    @animate = animate
  end

  def to_s
    return ''.html_safe if html.blank?

    html_safe = html.html_safe?

    if html_safe
      rewrite_custom_emojis(html)
    else
      ERB::Util.html_escape(rewrite_custom_emojis(html))
    end.html_safe # rubocop:disable Rails/OutputSafety
  end

  class << self
    def emojify(text, custom_emojis: nil, animate: true)
      return text if text.blank?

      new(text, custom_emojis: custom_emojis, animate: animate).to_s
    end
  end

  private

  def rewrite_custom_emojis(text)
    return text if custom_emojis.empty?

    # :shortcode: 形式の絵文字を画像タグに置換
    text.gsub(CustomEmoji::SCAN_RE) do |match|
      shortcode = ::Regexp.last_match(1)
      emoji = custom_emojis[shortcode]

      if emoji
        replacement_image_tag(emoji)
      else
        match
      end
    end
  end

  def replacement_image_tag(emoji)
    # 表示契機: 未キャッシュのリモート絵文字ならローカル取り込みを予約
    emoji.request_remote_image_cache if emoji.respond_to?(:request_remote_image_cache)
    image_url = animate? ? emoji.url : emoji.static_url
    image_alt = ":#{emoji.shortcode}:"

    # 画像タグの生成
    tag.img(
      src: image_url,
      alt: image_alt,
      title: image_alt,
      class: 'emojione custom-emoji',
      rel: 'emoji',
      draggable: 'false',
      # 直リンク時、リモートCDNのReferer型ホットリンク保護を避けるためRefererを送らない
      referrerpolicy: 'no-referrer'
    )
  end

  def animate?
    @animate
  end
end
