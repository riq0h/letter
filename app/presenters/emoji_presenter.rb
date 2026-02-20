# frozen_string_literal: true

# 絵文字表示ロジックを専門的に扱うPresenter
# HTML生成とコード処理を分離
class EmojiPresenter
  EMOJI_REGEX = CustomEmoji::SCAN_RE

  def initialize(text, domain: nil)
    @text = text.to_s
    @domain = domain
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

  # ショートコードを抽出（プレーンテキストの:shortcode:と<img alt=":shortcode:">の両方に対応）
  def extract_shortcodes
    shortcodes = @text.scan(EMOJI_REGEX).flatten
    # <img>タグのalt属性からも抽出（リモートサーバが事前レンダリング済みの場合）
    shortcodes += @text.scan(/<img[^>]*alt=":([^"]+):"[^>]*>/i).flatten
    shortcodes.map(&:downcase).uniq
  end

  # 使用されている絵文字のリストを取得
  def used_emojis
    shortcodes = extract_shortcodes
    return [] if shortcodes.empty?

    local_emojis = CustomEmoji.enabled.visible.where(shortcode: shortcodes, domain: nil)

    # ドメインが指定されている場合、そのドメインを優先して検索
    remote_emojis = if @domain.present?
                      domain_emojis = CustomEmoji.enabled.remote.where(shortcode: shortcodes, domain: @domain)
                      # ドメイン指定で見つからなかったショートコードは全ドメインから検索
                      remaining = shortcodes - domain_emojis.pluck(:shortcode)
                      if remaining.any?
                        domain_emojis + CustomEmoji.enabled.remote.where(shortcode: remaining)
                      else
                        domain_emojis
                      end
                    else
                      CustomEmoji.enabled.remote.where(shortcode: shortcodes)
                    end

    (local_emojis + remote_emojis).uniq(&:shortcode)
  end

  # クラスメソッド
  class << self
    # テキストを絵文字HTML付きで表示
    def present_with_emojis(text)
      new(text).to_html
    end

    # テキストから絵文字のリストを抽出（ドメイン指定可能）
    def extract_emojis_from(text, domain: nil)
      new(text, domain: domain).used_emojis
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

    # ドメイン指定がある場合はそのドメインを優先
    if @domain.present?
      @remote_emojis[normalized_shortcode] ||= CustomEmoji.enabled
                                                          .remote
                                                          .find_by(shortcode: normalized_shortcode, domain: @domain) ||
                                               CustomEmoji.enabled
                                                          .remote
                                                          .find_by(shortcode: normalized_shortcode)
    else
      @remote_emojis[normalized_shortcode] ||= CustomEmoji.enabled
                                                          .remote
                                                          .find_by(shortcode: normalized_shortcode)
    end
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
