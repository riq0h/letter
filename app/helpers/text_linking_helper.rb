# frozen_string_literal: true

require 'English'
module TextLinkingHelper
  def auto_link_urls(text)
    return ''.html_safe if text.blank?

    if text.include?('<') && text.include?('>')
      sanitized = sanitize_html_for_display(text)
      linked_text = apply_url_links_to_html(sanitized)
      mention_linked_text = apply_mention_links_to_html(linked_text)
      hashtag_linked_text = apply_hashtag_links_to_html(mention_linked_text)
    else
      escaped_text = escape_and_format_text(text)
      linked_text = apply_url_links(escaped_text)
      mention_linked_text = apply_mention_links(linked_text)
      hashtag_linked_text = apply_hashtag_links(mention_linked_text)
      # URLリンク化の後に改行を<br>に変換（URL内に<br>が混入するのを防ぐ）
      hashtag_linked_text = hashtag_linked_text.gsub("\n", '<br>')
    end
    hashtag_linked_text.html_safe
  end

  # 絵文字HTMLタグ (<img ... alt=":shortcode:" ...>) をショートコード形式 (:shortcode:) に変換
  def convert_emoji_html_to_shortcode(text)
    return text if text.blank?

    text.gsub(/<img[^>]*alt=":([^"]+):"[^>]*\/?>/, ':\1:')
  end

  def extract_urls_from_content(content)
    return [] if content.blank?

    urls = []

    # まずプレーンテキストのURLを抽出（ローカル投稿など、未処理のテキスト用）
    # これがないとWeb UIでローカル投稿のプレビューが表示されない
    content.scan(/(https?:\/\/[^\s<>＜＞"']+)/i) do |url|
      url_text = url[0]
      urls << url_text
    end

    # HTMLリンク化済みの場合も <a href="URL">形式のURLを抽出（API側との互換性）
    # ただし、ハッシュタグリンク（/tags/やclassにhashtag含む）は除外
    content.scan(/<a[^>]+href=["']([^"']+)["'][^>]*>/i) do |match|
      href = match[0]
      full_tag = ::Regexp.last_match(0) # マッチした全体のタグ

      # ハッシュタグリンクの場合はスキップ
      # /tags/ で始まるパス、または class属性に hashtag が含まれる場合
      if !(href.start_with?('/tags/') || full_tag.include?('hashtag')) && urls.none? do |existing_url|
        existing_url.include?(href) || href.include?(existing_url)
      end
        # プレーンテキストで既に見つからなかった場合のみ追加（重複回避）
        urls << href
      end
    end

    urls.uniq.select { |url| valid_preview_url?(url) }
  end

  def valid_preview_url?(url)
    return false if url.blank?

    begin
      uri = URI.parse(url)
      return false unless %w[http https].include?(uri.scheme)
      return false if uri.host.blank?

      # 有効なTLDを持つドメインか確認（例: "www." のような不完全なドメインを除外）
      return false unless uri.host.match?(/\.[a-z]{2,}\z/i)

      # Blueskyドメインは除外
      bluesky_domains = ['bsky.app', 'bsky.social', 'bsky.brid.gy']
      return false if bluesky_domains.any? { |domain| uri.host&.include?(domain) }

      # ActivityPubのユーザリンク（メンション）は除外
      # /users/username や /@username 形式のパスを除外
      return false if /^\/(users\/|@)/.match?(uri.path)

      # ハッシュタグリンクは除外
      # /tags/hashtag 形式のパスを除外
      return false if /^\/tags\//.match?(uri.path)

      # 画像・動画・音声ファイルは除外
      path = uri.path.downcase
      media_extensions = %w[.jpg .jpeg .png .gif .webp .mp4 .mp3 .wav .avi .mov .pdf]
      return false if media_extensions.any? { |ext| path.end_with?(ext) }

      true
    rescue URI::InvalidURIError
      false
    end
  end

  private

  def sanitize_html_for_display(html)
    # LoofahベースのサニタイザーでリモートHTMLコンテンツを安全にする
    # script, style, iframe, form等の危険なタグとイベントハンドラ属性を除去
    sanitizer = Rails::HTML5::SafeListSanitizer.new
    sanitizer.sanitize(
      html,
      tags: %w[p br a span em strong b i u del blockquote pre code ul ol li h1 h2 h3 h4 h5 h6 div img],
      attributes: %w[href class rel target translate src alt title width height loading]
    )
  end

  def escape_and_format_text(text)
    plain_text = CGI.unescapeHTML(ActionView::Base.full_sanitizer.sanitize(text).strip)
    # 注意: <br>変換はURLリンク化の後に行う（apply_url_linksが<br>を跨いでマッチするのを防ぐため）
    ERB::Util.html_escape(plain_text)
  end

  def apply_url_links(text)
    # 全角＜＞もURLの区切りとして扱う
    # www.で始まるURLもマッチ対象に含める
    link_pattern = /(https?:\/\/[^\s<>＜＞"']+|www\.[^\s<>＜＞"']+)/
    text.gsub(link_pattern) do
      url = ::Regexp.last_match(1)
      # www.で始まる場合はhttps://を補完
      href = url.start_with?('www.') ? "https://#{url}" : url
      display_text = mask_protocol(href)
      "<a href=\"#{href}\" target=\"_blank\" rel=\"noopener noreferrer\" " \
        "class=\"text-gray-500 hover:text-gray-700 transition-colors\">#{display_text}</a>"
    end
  end

  def apply_hashtag_links(text)
    base_url = Rails.application.config.activitypub.base_url
    hashtag_pattern = /(?<=\A|[\s>])#([\w\u0080-\uFFFF][\w\u0080-\uFFFF-]*)/
    text.gsub(hashtag_pattern) do
      tag_name = ::Regexp.last_match(1)
      normalized = tag_name.unicode_normalize(:nfkc).downcase
      tag_url = "#{base_url}/tags/#{ERB::Util.url_encode(normalized)}"
      %(<a href="#{tag_url}" class="mention hashtag" rel="tag">#<span>#{CGI.escapeHTML(tag_name)}</span></a>)
    end
  end

  def apply_hashtag_links_to_html(html_text)
    base_url = Rails.application.config.activitypub.base_url
    hashtag_pattern = /(?<=\A|[\s>])#([\w\u0080-\uFFFF][\w\u0080-\uFFFF-]*)/

    a_tag_ranges = collect_a_tag_ranges(html_text)

    result = html_text.dup
    offset = 0

    html_text.scan(hashtag_pattern) do |match|
      tag_name = match[0]
      match_start = $LAST_MATCH_INFO.begin(0)
      match_end = $LAST_MATCH_INFO.end(0)

      # 先頭のスペース等を含まないよう、#の位置を特定
      hash_pos = html_text.index('#', match_start)
      next unless hash_pos

      inside_a_tag = a_tag_ranges.any? { |range| hash_pos >= range[:start] && match_end <= range[:end] }

      unless inside_a_tag
        normalized = tag_name.unicode_normalize(:nfkc).downcase
        tag_url = "#{base_url}/tags/#{ERB::Util.url_encode(normalized)}"
        link = %(<a href="#{tag_url}" class="mention hashtag" rel="tag">#<span>#{CGI.escapeHTML(tag_name)}</span></a>)

        actual_start = hash_pos + offset
        actual_end = match_end + offset
        original_text = "##{tag_name}"
        result[actual_start...actual_end] = link
        offset += link.length - original_text.length
      end
    end

    result
  end

  def apply_mention_links(text)
    mention_pattern = /@([a-zA-Z0-9_.-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/
    text.gsub(mention_pattern) do
      username = ::Regexp.last_match(1)
      domain = ::Regexp.last_match(2)
      mention_url = build_mention_url(username, domain)
      # ActivityPub標準のh-card形式でメンションを作成（XSS防止のためエスケープ）
      %(<a href="#{CGI.escapeHTML(mention_url)}" class="h-card u-url mention"><span class="p-nickname">@#{CGI.escapeHTML(username)}</span></a>)
    end
  end

  def apply_url_links_to_html(html_text)
    # ActivityPub実装による分割URLリンクを完全なURLに変換
    html_text = fix_split_url_links(html_text)

    # 完全にHTMLリンク化済みコンテンツ（すべてのURLがリンク済み）の場合はスキップ
    # ただし、プレーンテキストURLがある場合は処理を続行
    urls_in_text = html_text.scan(/(https?:\/\/[^\s<>＜＞"']+)/)
    return html_text if urls_in_text.empty?

    # すべてのURLが既にリンク化されているかチェック
    all_urls_linked = urls_in_text.all? do |url_match|
      url = url_match[0]
      html_text.include?("<a href=\"#{url}\"") || html_text.include?("<a href='#{url}'")
    end

    return html_text if all_urls_linked

    link_urls_outside_tags(html_text)
  end

  def link_urls_outside_tags(html_text)
    # まず、既存のHTMLタグ位置を記録
    tags = []
    html_text.scan(/<[^>]+>/) { |_match| tags << { start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) } }

    # 既存のaタグ全体の範囲を記録（タグ内テキストもリンク化対象外にする）
    a_tag_ranges = collect_a_tag_ranges(html_text)

    # www.で始まるURLもマッチ対象に含める
    url_pattern = /(https?:\/\/[^\s<>＜＞"']+|www\.[^\s<>＜＞"']+)/
    result = html_text.dup
    offset = 0

    html_text.scan(url_pattern) do |url|
      url_start = $LAST_MATCH_INFO.begin(0)
      url_end = $LAST_MATCH_INFO.end(0)

      inside_tag = tags.any? { |tag| url_start >= tag[:start] && url_end <= tag[:end] }
      inside_a_tag = a_tag_ranges.any? { |range| url_start >= range[:start] && url_end <= range[:end] }

      unless inside_tag || inside_a_tag
        href = url[0].start_with?('www.') ? "https://#{url[0]}" : url[0]
        display_text = mask_protocol(href)
        linked_url = "<a href=\"#{href}\" target=\"_blank\" rel=\"noopener noreferrer\" " \
                     "class=\"text-gray-500 hover:text-gray-700 transition-colors\">#{display_text}</a>"

        actual_start = url_start + offset
        actual_end = url_end + offset
        result[actual_start...actual_end] = linked_url
        offset += linked_url.length - url[0].length
      end
    end

    result
  end

  def collect_a_tag_ranges(html_text)
    ranges = []
    html_text.scan(/<a\b[^>]*>.*?<\/a>/mi) do |_match|
      ranges << { start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) }
    end
    ranges
  end

  def apply_mention_links_to_html(html_text)
    # まず、リモートサーバからの複雑なメンション構造を正規化する
    html_text = normalize_mention_html(html_text)

    mention_pattern = /@([a-zA-Z0-9_.-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/

    # 既存のaタグ全体（開始タグから終了タグまで）の位置を記録
    a_tags = []
    html_text.scan(/<a\b[^>]*>.*?<\/a>/mi) do |match|
      a_tags << { content: match, start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) }
    end

    result = html_text.dup
    offset = 0

    html_text.scan(mention_pattern) do |match|
      username = match[0]
      domain = match[1]
      mention_start = $LAST_MATCH_INFO.begin(0)
      mention_end = $LAST_MATCH_INFO.end(0)

      # このメンションが既存のaタグ内にないかチェック
      inside_a_tag = a_tags.any? do |tag|
        mention_start >= tag[:start] && mention_end <= tag[:end]
      end

      offset = replace_mention_with_link(result, username, domain, mention_start..mention_end, offset) unless inside_a_tag
    end

    result
  end

  def replace_mention_with_link(result, username, domain, mention_range, offset)
    mention_url = build_mention_url(username, domain)
    escaped_url = CGI.escapeHTML(mention_url)
    escaped_text = CGI.escapeHTML("@#{username}")
    linked_mention = "<a href=\"#{escaped_url}\" class=\"h-card u-url mention\">" \
                     "<span class=\"p-nickname\">#{escaped_text}</span></a>"

    actual_range = (mention_range.begin + offset)...(mention_range.end + offset)
    original_mention = "@#{username}@#{domain}"
    result[actual_range] = linked_mention
    offset + linked_mention.length - original_mention.length
  end

  def build_mention_url(username, domain)
    safe_username = username.gsub(/[^\w.-]/u, '')
    safe_domain = domain.gsub(/[^\w.\-:\/]/u, '')

    return '#' if safe_username.empty? || safe_domain.empty?

    local_domain = Rails.application.config.activitypub.domain

    if domain == local_domain
      # ローカルユーザの場合（クライアント互換のためAPI形式URLを使用）
      "#{Rails.application.config.activitypub.base_url}/users/#{ERB::Util.url_encode(safe_username)}"
    else
      # リモートユーザの場合、Actorレコードから正しいURLを取得を試行
      actor = Actor.find_by(username: safe_username, domain: safe_domain)
      if actor&.ap_id.present?
        # ap_idがhttp/httpsプロトコルであることを検証（javascript:等のXSS防止）
        actor_url = actor.ap_id
        return '#' unless actor_url.start_with?('https://', 'http://')

        actor_url
      else
        # Actorレコードがない場合は一般的なパターンを使用（クライアント互換のためAPI形式）
        "https://#{ERB::Util.url_encode(safe_domain)}/users/#{ERB::Util.url_encode(safe_username)}"
      end
    end
  end

  def mask_protocol(url)
    # https://をマスクして表示
    return url unless url.start_with?('https://')

    url.delete_prefix('https://')
  end

  def normalize_mention_html(html_text)
    # リモートサーバからの複雑なメンション構造をMastodon標準のh-card形式に正規化
    # 参考: https://docs.joinmastodon.org/spec/microformats/#h-card

    result = html_text.dup

    # パターン1: @マークがaタグ外にある場合
    # <span class="h-card"><a href="URL" class="u-url mention">@<span>username</span></a></span>
    result = result.gsub(/<span class="h-card">\s*<a\s+([^>]*href=["']([^"']+)["'][^>]*)\s*>\s*@<span>([^<]+)<\/span>\s*<\/a>\s*<\/span>/mi) do
      href_url = ::Regexp.last_match(2)
      username = ::Regexp.last_match(3)

      # ActivityPub標準のh-card形式に変換（XSS防止のためエスケープ）
      %(<a href="#{CGI.escapeHTML(href_url)}" class="h-card u-url mention"><span class="p-nickname">@#{CGI.escapeHTML(username)}</span></a>)
    end

    # パターン2: @マークがspan内にある場合
    # <span class="h-card" translate="no"><a class="u-url mention" href="URL"><span>@username</span></a></span>
    result.gsub(/<span class="h-card"[^>]*>\s*<a\s+([^>]*href=["']([^"']+)["'][^>]*)\s*>\s*<span>@([^<]+)<\/span>\s*<\/a>\s*<\/span>/mi) do
      href_url = ::Regexp.last_match(2)
      username = ::Regexp.last_match(3)

      # ActivityPub標準のh-card形式に変換（XSS防止のためエスケープ）
      %(<a href="#{CGI.escapeHTML(href_url)}" class="h-card u-url mention"><span class="p-nickname">@#{CGI.escapeHTML(username)}</span></a>)
    end
  end

  def fix_split_url_links(html_text)
    # ActivityPub実装（Mastodon等）が送信する分割されたURLリンクを修正
    # 例: <a href="URL"><span class="invisible">https://www.</span><span class="ellipsis">example.com/path</span><span class="invisible">...</span></a>
    # invisibleスパンを削除し、ellipsisスパンの内容を表示テキストとして使用

    html_text.gsub(/<a\s+([^>]*href=["']([^"']+)["'][^>]*)>(.+?)<\/a>/m) do |match|
      attributes = ::Regexp.last_match(1)
      href_url = ::Regexp.last_match(2)
      link_content = ::Regexp.last_match(3)

      # span.invisibleやspan.ellipsisを含むリンクの場合
      if link_content.include?('class="invisible"') || link_content.include?('class="ellipsis"')
        # invisibleスパンを削除し、ellipsisスパンの内容を抽出
        cleaned_content = link_content.gsub(/<span class="invisible">[^<]*<\/span>/, '')
                                      .gsub(/<span class="ellipsis">([^<]*)<\/span>/, '\1')
                                      .strip

        # 空になった場合は元のhref URLを使用し、プロトコルをマスク
        display_text = if cleaned_content.empty?
                         mask_protocol(href_url)
                       else
                         # ellipsisスパンがあった場合は省略されていることを示すため...を付ける
                         link_content.include?('class="ellipsis"') ? "#{cleaned_content}..." : cleaned_content
                       end

        "<a #{attributes}>#{display_text}</a>"
      else
        # それ以外は元のまま
        match
      end
    end
  end
end
