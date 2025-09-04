# frozen_string_literal: true

require 'English'
module TextLinkingHelper
  def auto_link_urls(text)
    return ''.html_safe if text.blank?

    if text.include?('<') && text.include?('>')
      linked_text = apply_url_links_to_html(text)
      mention_linked_text = apply_mention_links_to_html(linked_text)
    else
      escaped_text = escape_and_format_text(text)
      linked_text = apply_url_links(escaped_text)
      mention_linked_text = apply_mention_links(linked_text)
    end
    mention_linked_text.html_safe
  end

  def extract_urls_from_content(content)
    return [] if content.blank?

    # <a href="URL">形式のURLを抽出（これが最も正確）
    urls = content.scan(/<a[^>]+href=["']([^"']+)["'][^>]*>/i).flatten

    # プレーンテキストのURLも追加抽出（aタグに含まれていないもの）
    content.scan(/(https?:\/\/[^\s<>"']+)/i) do |url|
      url_text = url[0]
      # すでにaタグのhref属性に含まれていない場合のみ追加
      urls << url_text unless urls.any? { |existing_url| existing_url.include?(url_text) || url_text.include?(existing_url) }
    end

    urls.uniq.select { |url| valid_preview_url?(url) }
  end

  def valid_preview_url?(url)
    return false if url.blank?

    begin
      uri = URI.parse(url)
      return false unless %w[http https].include?(uri.scheme)
      return false if uri.host.blank?

      # ActivityPubのユーザリンク（メンション）は除外
      # /users/username や /@username 形式のパスを除外
      return false if /^\/(users\/|@)/.match?(uri.path)

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

  def escape_and_format_text(text)
    plain_text = ActionView::Base.full_sanitizer.sanitize(text).strip
    ERB::Util.html_escape(plain_text).gsub("\n", '<br>')
  end

  def apply_url_links(text)
    link_pattern = /(https?:\/\/[^\s]+)/
    text.gsub(link_pattern) do
      url = ::Regexp.last_match(1)
      display_text = mask_protocol(url)
      "<a href=\"#{url}\" target=\"_blank\" rel=\"noopener noreferrer\" " \
        "class=\"text-gray-500 hover:text-gray-700 transition-colors\">#{display_text}</a>"
    end
  end

  def apply_mention_links(text)
    mention_pattern = /@([a-zA-Z0-9_.-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/
    text.gsub(mention_pattern) do
      username = ::Regexp.last_match(1)
      domain = ::Regexp.last_match(2)
      mention_url = build_mention_url(username, domain)
      # ActivityPub標準のh-card形式でメンションを作成
      %(<a href="#{mention_url}" class="h-card u-url mention"><span class="p-nickname">@#{username}</span></a>)
    end
  end

  def apply_url_links_to_html(html_text)
    # ActivityPub実装による分割URLリンクを完全なURLに変換
    html_text = fix_split_url_links(html_text)

    # 完全にHTMLリンク化済みコンテンツ（すべてのURLがリンク済み）の場合はスキップ
    # ただし、プレーンテキストURLがある場合は処理を続行
    urls_in_text = html_text.scan(/(https?:\/\/[^\s<>"']+)/)
    return html_text if urls_in_text.empty?

    # すべてのURLが既にリンク化されているかチェック
    all_urls_linked = urls_in_text.all? do |url_match|
      url = url_match[0]
      html_text.include?("<a href=\"#{url}\"") || html_text.include?("<a href='#{url}'")
    end

    return html_text if all_urls_linked

    # HTMLタグの外側にあるURLのみをリンク化する
    # 既存のaタグ、imgタグなどを壊さないように注意深く処理

    # まず、既存のHTMLタグ位置を記録
    tags = []
    html_text.scan(/<[^>]+>/) { |match| tags << { content: match, start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) } }

    # URLパターンを探してリンク化（ただし、既存のタグ内は除外）
    url_pattern = /(https?:\/\/[^\s<>"']+)/
    result = html_text.dup
    offset = 0

    html_text.scan(url_pattern) do |url|
      url_start = $LAST_MATCH_INFO.begin(0)
      url_end = $LAST_MATCH_INFO.end(0)

      # このURLが既存のHTMLタグ内にないかチェック
      inside_tag = tags.any? do |tag|
        url_start >= tag[:start] && url_end <= tag[:end]
      end

      unless inside_tag
        # リンク化
        display_text = mask_protocol(url[0])
        linked_url = "<a href=\"#{url[0]}\" target=\"_blank\" rel=\"noopener noreferrer\" " \
                     "class=\"text-gray-500 hover:text-gray-700 transition-colors\">#{display_text}</a>"

        # オフセットを考慮して置換
        actual_start = url_start + offset
        actual_end = url_end + offset
        result[actual_start...actual_end] = linked_url
        offset += linked_url.length - url[0].length
      end
    end

    result
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

      unless inside_a_tag
        mention_url = build_mention_url(username, domain)
        display_text = "@#{username}"

        linked_mention = "<a href=\"#{mention_url}\" class=\"h-card u-url mention\"><span class=\"p-nickname\">#{display_text}</span></a>"

        # オフセットを考慮して置換
        actual_start = mention_start + offset
        actual_end = mention_end + offset
        original_mention = "@#{username}@#{domain}"
        result[actual_start...actual_end] = linked_mention
        offset += linked_mention.length - original_mention.length
      end
    end

    result
  end

  def build_mention_url(username, domain)
    safe_username = username.gsub(/[^a-zA-Z0-9_.-]/, '')
    safe_domain = domain.gsub(/[^a-zA-Z0-9.-]/, '')

    return '#' if safe_username.empty? || safe_domain.empty?

    local_domain = Rails.application.config.activitypub.domain

    if domain == local_domain
      # ローカルユーザの場合
      "#{Rails.application.config.activitypub.base_url}/@#{ERB::Util.url_encode(safe_username)}"
    else
      # リモートユーザの場合、Actorレコードから正しいURLを取得を試行
      actor = Actor.find_by(username: safe_username, domain: safe_domain)
      if actor&.ap_id.present?
        # ap_idが完全なURLの場合はそのまま使用、そうでなければhttpsを追加
        actor_url = actor.ap_id
        actor_url.start_with?('http') ? actor_url : "https://#{actor_url}"
      else
        # Actorレコードがない場合は一般的なパターンを使用（暫定）
        "https://#{ERB::Util.url_encode(safe_domain)}/@#{ERB::Util.url_encode(safe_username)}"
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

      # ActivityPub標準のh-card形式に変換
      %(<a href="#{href_url}" class="h-card u-url mention"><span class="p-nickname">@#{username}</span></a>)
    end

    # パターン2: @マークがspan内にある場合
    # <span class="h-card" translate="no"><a class="u-url mention" href="URL"><span>@username</span></a></span>
    result.gsub(/<span class="h-card"[^>]*>\s*<a\s+([^>]*href=["']([^"']+)["'][^>]*)\s*>\s*<span>@([^<]+)<\/span>\s*<\/a>\s*<\/span>/mi) do
      href_url = ::Regexp.last_match(2)
      username = ::Regexp.last_match(3)

      # ActivityPub標準のh-card形式に変換
      %(<a href="#{href_url}" class="h-card u-url mention"><span class="p-nickname">@#{username}</span></a>)
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
