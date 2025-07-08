# frozen_string_literal: true

# 絵文字表示ロジックを専門的に扱うPresenter
# HTML生成とコード処理を分離
class EmojiPresenter
  EMOJI_REGEX = /:([a-zA-Z0-9_]+):/

  def initialize(text)
    @text = text.to_s
    @local_emojis = {}
    @remote_emojis = {}
  end

  # 絵文字をHTMLに変換
  def to_html
    @text.gsub(EMOJI_REGEX) do |match|
      shortcode = Regexp.last_match(1)
      emoji = find_emoji(shortcode)

      if emoji
        build_emoji_html(emoji)
      else
        match # 絵文字が見つからない場合は元のテキストを返す
      end
    end
  end

  # ショートコードを抽出
  def extract_shortcodes
    @text.scan(EMOJI_REGEX).flatten.uniq
  end

  # 使用されている絵文字のリストを取得
  def used_emojis
    shortcodes = extract_shortcodes
    return [] if shortcodes.empty?

    normalized_shortcodes = shortcodes.map(&:downcase)

    local_emojis = CustomEmoji.enabled.visible.where(shortcode: normalized_shortcodes, domain: nil)
    remote_emojis = CustomEmoji.enabled.remote.where(shortcode: normalized_shortcodes)

    (local_emojis + remote_emojis).uniq(&:shortcode)
  end

  # クラスメソッド
  class << self
    # テキストを絵文字HTML付きで表示
    def present_with_emojis(text)
      new(text).to_html
    end

    # テキストから絵文字のリストを抽出
    def extract_emojis_from(text)
      new(text).used_emojis
    end

    # ショートコードのみを抽出
    def extract_shortcodes_from(text)
      new(text).extract_shortcodes
    end
  end

  private

  # 絵文字を検索（キャッシュ付き）
  def find_emoji(shortcode)
    normalized_shortcode = shortcode.downcase

    @local_emojis[normalized_shortcode] ||= CustomEmoji.enabled
                                                       .visible
                                                       .find_by(shortcode: normalized_shortcode, domain: nil)

    return @local_emojis[normalized_shortcode] if @local_emojis[normalized_shortcode]

    @remote_emojis[normalized_shortcode] ||= CustomEmoji.enabled
                                                        .remote
                                                        .find_by(shortcode: normalized_shortcode)
  end

  # 絵文字HTML要素を構築
  def build_emoji_html(emoji)
    style = emoji_inline_style
    alt_text = ":#{emoji.shortcode}:"

    <<~HTML.strip
      <img src="#{emoji.image_url}" alt="#{alt_text}" title="#{alt_text}" class="custom-emoji" style="#{style}" draggable="false" />
    HTML
  end

  # 絵文字用のインラインスタイル
  def emoji_inline_style
    'width: 1.2em; height: 1.2em; display: inline-block; ' \
      'vertical-align: text-bottom; object-fit: contain;'
  end
end
