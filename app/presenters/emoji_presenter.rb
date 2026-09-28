# frozen_string_literal: true

# 絵文字表示ロジックを専門的に扱うPresenter
# HTML生成とコード処理を分離
class EmojiPresenter
  EMOJI_REGEX = CustomEmoji::SCAN_RE
  # Misskey系のドメイン修飾形 :name@host: (他サーバの絵文字参照。送信側がtagを付けないことがある)。
  # 表示専用: (name, host)がキャッシュに実在する時だけ置換し、未知の絵文字の取得や送信側の扱いは変えない
  QUALIFIED_EMOJI_REGEX = /:(#{CustomEmoji::SHORTCODE_RE_FRAGMENT})@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+):/o
  RENDER_REGEX = /#{QUALIFIED_EMOJI_REGEX}|#{EMOJI_REGEX}/o

  def initialize(text, domain: nil)
    @text = text.to_s
    @domain = domain
    @resolved_emojis = {}
    @remote_emojis = {}
  end

  # 絵文字をHTMLに変換
  def to_html
    @text.gsub(RENDER_REGEX) do |match|
      m = Regexp.last_match
      emoji = m[2] ? find_qualified_emoji(m[1], m[2]) : find_emoji(m[3])

      if emoji
        build_emoji_html(emoji)
      else
        match # 絵文字が見つからない場合は元のテキストを返す
      end
    end
  end

  # ショートコードを抽出（プレーンテキストの:shortcode:と<img alt=":shortcode:">の両方に対応）
  def extract_shortcodes
    raw_shortcodes.map(&:downcase).uniq
  end

  # 大文字小文字を保持したまま抽出する。Mastodon系クライアントは本文中の
  # :ShortCode: と API の emojis 配列内 shortcode を大文字小文字を区別して照合するため、
  # API出力では本文に現れた通りの表記を保持しないと絵文字化されない。
  # （DB保存値はdowncaseで統一しているため、URL解決はdowncaseキーで行う）
  def extract_raw_shortcodes
    raw_shortcodes.uniq
  end

  # 使用されている絵文字のリストを取得
  def used_emojis
    # ドメイン修飾形は表示専用のため対象外(送信するtagに載せない)
    shortcodes = extract_shortcodes.reject { |c| c.include?('@') }
    return [] if shortcodes.empty?

    # 優先順: 投稿者/アカウントのドメイン → ローカル → 他ドメイン(同名絵文字は多数のサーバに存在するため
    # 先頭一致で選ぶと別サーバの版、さらにはリモートの人の名前にローカル版が出てしまう)
    domain_emojis = @domain.present? ? CustomEmoji.enabled.remote.where(shortcode: shortcodes, domain: @domain).to_a : []
    remaining = shortcodes - domain_emojis.map(&:shortcode)
    local_emojis = remaining.any? ? CustomEmoji.enabled.visible.where(shortcode: remaining, domain: nil).to_a : []
    remaining -= local_emojis.map(&:shortcode)
    other_emojis = remaining.any? ? CustomEmoji.enabled.remote.where(shortcode: remaining).to_a : []

    (domain_emojis + local_emojis + other_emojis).uniq(&:shortcode)
  end

  # クラスメソッド
  class << self
    # テキストを絵文字HTML付きで表示
    def present_with_emojis(text, domain: nil)
      new(text, domain: domain).to_html
    end

    # テキストから絵文字のリストを抽出（ドメイン指定可能）
    def extract_emojis_from(text, domain: nil)
      new(text, domain: domain).used_emojis
    end

    # "name@host"形式のトークンを[name, host](小文字)に分解。修飾形でなければnil
    def split_qualified(token)
      name, host = token.to_s.downcase.split('@', 2)
      host.present? && name.present? ? [name, host] : nil
    end

    # ショートコードのみを抽出
    def extract_shortcodes_from(text)
      new(text).extract_shortcodes
    end

    # 大文字小文字を保持したショートコードを抽出（API emojis配列用）
    def extract_raw_shortcodes_from(text)
      new(text).extract_raw_shortcodes
    end
  end

  private

  # :shortcode: 形式と <img alt=":shortcode:"> の両方からショートコードを収集（表記そのまま）
  def raw_shortcodes
    shortcodes = @text.scan(EMOJI_REGEX).flatten
    # ドメイン修飾形は "name@host" トークンとして扱う
    shortcodes += @text.scan(QUALIFIED_EMOJI_REGEX).map { |name, host| "#{name}@#{host}" }
    # <img>タグのalt属性からも抽出（リモートサーバが事前レンダリング済みの場合）
    shortcodes + @text.scan(/<img[^>]*alt=":([^"]+):"[^>]*>/i).flatten
  end

  # 絵文字を検索（キャッシュ付き）
  def find_emoji(shortcode)
    key = shortcode.downcase
    return @resolved_emojis[key] if @resolved_emojis.key?(key)

    # 優先順は used_emojis と同じ: 指定ドメイン → ローカル → 他ドメイン
    @resolved_emojis[key] =
      (@domain.present? && CustomEmoji.enabled.remote.find_by(shortcode: key, domain: @domain)) ||
      CustomEmoji.enabled.visible.find_by(shortcode: key, domain: nil) ||
      CustomEmoji.enabled.remote.find_by(shortcode: key)
  end

  # ドメイン修飾形: 指定ドメインの絵文字のみ(他ドメインへのフォールバックはしない)
  def find_qualified_emoji(name, host)
    key = "#{name.downcase}@#{host.downcase}"
    return @remote_emojis[key] if @remote_emojis.key?(key)

    @remote_emojis[key] = CustomEmoji.enabled.remote.find_by(shortcode: name.downcase, domain: host.downcase)
  end

  # 絵文字HTML要素を構築
  def build_emoji_html(emoji)
    # 表示契機: 未キャッシュのリモート絵文字ならローカル取り込みを予約
    emoji.request_remote_image_cache if emoji.respond_to?(:request_remote_image_cache)
    style = emoji_inline_style
    alt_text = ":#{emoji.shortcode}:"

    # referrerpolicy=no-referrer: 直リンク時にリモートCDNのReferer型ホットリンク保護を避ける
    <<~HTML.strip
      <img src="#{emoji.image_url}" alt="#{alt_text}" title="#{alt_text}" class="custom-emoji" style="#{style}" draggable="false" referrerpolicy="no-referrer" />
    HTML
  end

  # 絵文字用のインラインスタイル
  def emoji_inline_style
    'width: 1.2em; height: 1.2em; display: inline-block; ' \
      'vertical-align: text-bottom; object-fit: contain;'
  end
end
