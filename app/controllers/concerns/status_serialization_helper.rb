# frozen_string_literal: true

module StatusSerializationHelper
  extend ActiveSupport::Concern
  include AccountSerializer
  include MediaSerializer
  include MentionTagSerializer
  include TextLinkingHelper
  include StatusSerializer
  include PollSerializer

  private

  def serialized_status(status)
    # moshidonクライアント互換性のための堅牢なStatus serialization
    return default_status_structure unless status

    begin
      base_status_data(status)
        .merge(interaction_data(status))
        .merge(content_data(status))
        .merge(metadata_data(status))
        .merge(ensure_required_arrays)
    rescue StandardError => e
      Rails.logger.error "Critical error in serialized_status for #{status&.id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join(', ')}"
      default_status_structure
    end
  end

  def base_status_data(status)
    {
      id: status.id.to_s,
      created_at: status.published_at&.iso8601 || status.created_at.iso8601,
      edited_at: status.edited_at&.iso8601,
      uri: status.ap_id,
      url: status.public_url || status.ap_id,
      visibility: status.visibility || 'public',
      language: status.language,
      sensitive: status.sensitive?
    }
  end

  def interaction_data(status)
    {
      in_reply_to_id: in_reply_to_id(status),
      in_reply_to_account_id: in_reply_to_account_id(status),
      replies_count: status.replies_count || 0,
      reblogs_count: status.reblogs_count || 0,
      favourites_count: status.favourites_count || 0,
      favourited: favourited_by_current_user?(status),
      reblogged: reblogged_by_current_user?(status),
      muted: muted_by_current_user?(status),
      bookmarked: bookmarked_by_current_user?(status),
      pinned: pinned_by_current_user?(status),
      quoted: quoted_by_current_user?(status),
      filtered: [],
      application: status.local? ? { name: 'letter', website: nil } : nil
    }
  end

  def content_data(status)
    # API用: メンション・URLリンク化、絵文字はショートコード形式で保持
    linked_content = parse_content_for_api_with_mentions(status)

    {
      spoiler_text: status.summary || '',
      content: linked_content,
      account: serialized_account(status.actor),
      reblog: nil,
      quote: build_quote_data(status)
    }
  end

  def metadata_data(status)
    # moshidonが要求する必須配列フィールドを確実に提供
    {
      media_attachments: ensure_array(serialized_media_attachments(status)),
      mentions: ensure_array(serialized_mentions(status)),
      tags: ensure_array(serialized_tags(status)),
      emojis: ensure_array(serialized_emojis(status)),
      card: serialize_preview_card(status),
      poll: serialize_poll(status)
    }
  end

  def in_reply_to_id(status)
    reply_info = find_reply_to_info(status)
    reply_info&.dig(:id)&.to_s
  end

  def in_reply_to_account_id(status)
    reply_info = find_reply_to_info(status)
    reply_info&.dig(:actor_id)&.to_s
  end

  def find_reply_to_info(status)
    return nil if status.in_reply_to_ap_id.blank?

    # キャッシュされたリプライ先情報があれば使用
    return @reply_to_cache[status.in_reply_to_ap_id] if defined?(@reply_to_cache) && @reply_to_cache

    # フォールバック: 個別クエリ（同一ステータスでの重複クエリを防止）
    @reply_to_fallback_cache ||= {}
    unless @reply_to_fallback_cache.key?(status.in_reply_to_ap_id)
      obj = ActivityPubObject.find_by(ap_id: status.in_reply_to_ap_id)
      @reply_to_fallback_cache[status.in_reply_to_ap_id] = ({ id: obj.id, actor_id: obj.actor&.id } if obj)
    end
    @reply_to_fallback_cache[status.in_reply_to_ap_id]
  end

  # バッチプリロード: タイムライン全体のインタラクション状態を一括取得（N+1回避）
  def preload_interaction_data(statuses)
    return unless current_user

    status_ids = statuses.map(&:id)
    @favourited_ids = current_user.favourites.where(object_id: status_ids).pluck(:object_id).to_set
    @reblogged_ids = current_user.reblogs.where(object_id: status_ids).pluck(:object_id).to_set
    @bookmarked_ids = current_user.bookmarks.where(object_id: status_ids).pluck(:object_id).to_set
    @pinned_ids = current_user.pinned_statuses.where(object_id: status_ids).pluck(:object_id).to_set
    @quoted_ids = current_user.quote_posts.where(quoted_object_id: status_ids).pluck(:quoted_object_id).to_set
    @muted_account_ids = current_user.mutes.pluck(:target_actor_id).to_set
  end

  def favourited_by_current_user?(status)
    return false unless current_user
    return @favourited_ids.include?(status.id) if defined?(@favourited_ids) && @favourited_ids

    current_user.favourites.exists?(object: status)
  end

  def reblogged_by_current_user?(status)
    return false unless current_user
    return @reblogged_ids.include?(status.id) if defined?(@reblogged_ids) && @reblogged_ids

    current_user.reblogs.exists?(object: status)
  end

  def muted_by_current_user?(status)
    return false unless current_user

    # アカウントミュートに基づく（会話ミュートは未実装）
    return @muted_account_ids.include?(status.actor_id) if defined?(@muted_account_ids) && @muted_account_ids

    current_user.muting?(status.actor)
  end

  def bookmarked_by_current_user?(status)
    return false unless current_user
    return @bookmarked_ids.include?(status.id) if defined?(@bookmarked_ids) && @bookmarked_ids

    current_user.bookmarks.exists?(object: status)
  end

  def pinned_by_current_user?(status)
    # AccountsController#statusesの場合は、そのアカウントが固定した投稿かどうかを返す
    return status.actor.pinned_statuses.exists?(object: status) if params[:controller] == 'api/v1/accounts' && params[:action] == 'statuses'

    return false unless current_user
    return @pinned_ids.include?(status.id) if defined?(@pinned_ids) && @pinned_ids

    current_user.pinned_statuses.exists?(object: status)
  end

  def quoted_by_current_user?(status)
    return false unless current_user
    return @quoted_ids.include?(status.id) if defined?(@quoted_ids) && @quoted_ids

    current_user.quote_posts.exists?(quoted_object: status)
  end

  def build_quote_data(status)
    # キャッシュがあればそれを使用
    quote_post = if defined?(@quote_cache) && @quote_cache
                   @quote_cache[status.id]
                 else
                   status.quote_posts.first
                 end
    return nil unless quote_post

    quoted_object = quote_post.quoted_object
    return nil unless quoted_object

    quoted_actor = quoted_object.actor
    return nil unless quoted_actor

    {
      id: quoted_object.id.to_s,
      created_at: quoted_object.published_at&.iso8601,
      uri: quoted_object.ap_id,
      url: quoted_object.public_url,
      content: parse_content_for_api_with_mentions(quoted_object),
      account: serialized_account(quoted_actor),
      shallow_quote: quote_post.shallow_quote?
    }
  end

  def serialize_poll(status)
    poll = status.poll
    return nil unless poll

    result = poll.to_mastodon_api

    # 認証済みの場合は現在のユーザ固有データを追加
    if current_user
      # メモリ上で処理して2回のDBクエリを1回に削減
      user_votes = poll.poll_votes.where(actor: current_user).to_a
      result[:voted] = user_votes.any?
      result[:own_votes] = user_votes.map(&:choice)
    end

    result
  end

  def serialize_preview_card(status)
    return nil if status.content.blank?

    # キャッシュがあればそれを使用
    if defined?(@link_preview_cache) && @link_preview_cache
      link_preview = @link_preview_cache[status.id]
    else
      urls = extract_urls_from_content(status.content)
      return nil if urls.empty?

      preview_url = urls.first
      link_preview = LinkPreview.find_by(url: preview_url)
    end
    return nil if link_preview&.title.blank?

    {
      url: link_preview.url,
      title: link_preview.title || '',
      description: link_preview.description || '',
      type: link_preview.preview_type || 'link',
      author_name: '',
      author_url: '',
      provider_name: link_preview.site_name || '',
      provider_url: '',
      html: '',
      width: 0,
      height: 0,
      image: link_preview.image,
      embed_url: '',
      blurhash: nil
    }
  end

  # リプライ先情報をバルクで取得してキャッシュ
  def preload_reply_to_data(statuses)
    # リプライ先AP IDを収集
    reply_to_ap_ids = statuses.filter_map(&:in_reply_to_ap_id).uniq
    return unless reply_to_ap_ids.any?

    # 一度のクエリでリプライ先の情報を取得
    reply_objects = ActivityPubObject.where(ap_id: reply_to_ap_ids)
                                     .includes(:actor)
                                     .index_by(&:ap_id)

    # キャッシュ用のハッシュを構築
    @reply_to_cache = reply_objects.transform_values do |obj|
      {
        id: obj.id,
        actor_id: obj.actor&.id
      }
    end
  end

  # quote_posts情報をバルクで取得してキャッシュ
  def preload_quote_data(statuses)
    status_ids = statuses.map(&:id)
    quote_posts = QuotePost.where(object_id: status_ids)
                           .includes(quoted_object: :actor)
                           .to_a

    @quote_cache = {}
    quote_posts.each do |qp|
      @quote_cache[qp[:object_id]] ||= qp
    end
  end

  # link_preview情報をバルクで取得してキャッシュ
  def preload_link_previews(statuses)
    all_urls = {}
    statuses.each do |status|
      next if status.content.blank?

      urls = extract_urls_from_content(status.content)
      all_urls[urls.first] = status.id if urls.any?
    end

    return if all_urls.empty?

    previews = LinkPreview.where(url: all_urls.keys).index_by(&:url)
    @link_preview_cache = {}
    all_urls.each do |url, status_id|
      @link_preview_cache[status_id] = previews[url] if previews[url]
    end
  end

  # mentionsをバルクでプリロード
  def preload_mentions_data(statuses)
    status_ids = statuses.map(&:id)
    mentions = Mention.where(object_id: status_ids).includes(:actor).to_a
    @mentions_cache = {}
    mentions.each do |mention|
      (@mentions_cache[mention[:object_id]] ||= []) << mention
    end
  end

  # moshidon互換性のためのヘルパーメソッド
  def ensure_array(value)
    return [] if value.nil?
    return value if value.is_a?(Array)

    [value] # 単一の値を配列に変換
  end

  def ensure_required_arrays
    # moshidonの@RequiredFieldに対応
    {}
  end

  def parse_content_for_api_with_mentions(status)
    return '' if status.content.blank?

    content = status.content

    # リモートサーバからの複雑なメンション構造を正規化
    content = normalize_mention_html(content)

    # 既存のmentionレコードを使って正確なリンクを生成（ただし、既にリンク化済みの場合はスキップ）
    if status.mentions.any?
      status.mentions.includes(:actor).find_each do |mention|
        actor = mention.actor
        # フルメンション形式とローカルメンション形式の両方に対応
        # ローカルユーザの場合はdomainがnilなので、適切に処理
        full_mention = if actor.local?
                         "@#{actor.username}" # ローカルユーザにはドメイン部分なし
                       else
                         "@#{actor.username}@#{actor.domain}"
                       end
        local_mention = "@#{actor.username}"

        # 既にaタグ内に含まれていないかチェック（正規化後のh-card形式も含む）
        mention_already_linked = content.include?(%(<a href="#{actor.ap_id}")) ||
                                 (actor.domain && content.include?(%(<a href="https://#{actor.domain}/users/#{actor.username}"))) ||
                                 content.include?(%(>@#{actor.username}</a>)) ||
                                 content.include?(%(<span class="p-nickname">@#{actor.username}</span>))

        unless mention_already_linked
          # XSS防止: リモートアクターのap_idやusernameをHTMLエスケープ
          safe_ap_id = CGI.escapeHTML(actor.ap_id.to_s)
          safe_username = CGI.escapeHTML(actor.username.to_s)

          # ドメイン付きメンションを優先的に処理
          if content.include?(full_mention)
            # Mastodon標準のh-card形式でメンションを作成
            mention_link = %(<a href="#{safe_ap_id}" class="h-card mention"><span class="p-nickname">@#{safe_username}</span></a>)
            content = gsub_outside_a_tags(content, full_mention, mention_link)
          elsif content.include?(local_mention) && actor.local?
            # Mastodon標準のh-card形式でメンションを作成
            mention_link = %(<a href="#{safe_ap_id}" class="h-card mention"><span class="p-nickname">@#{safe_username}</span></a>)
            content = gsub_outside_a_tags(content, local_mention, mention_link)
          end
        end
      end
    end

    # 絵文字HTMLをショートコードに戻す（外部投稿の場合）
    content = parse_content_links_only(content) if content.include?('<img') && content.include?('custom-emoji')

    # ハッシュタグリンク化（status.tagsのDB情報を使用）
    content = apply_hashtag_links_to_content(content, status)

    # Mastodon形式の分割URLリンクを修正（防御的処理）
    content = fix_split_url_links(content)

    # URLリンク化（既存のaタグは保持）
    apply_url_links_only(content)
  end

  def apply_hashtag_links_to_content(content, status)
    return content unless status.respond_to?(:tags) && status.tags.any?

    base_url = Rails.application.config.activitypub.base_url

    status.tags.each do |tag|
      display_name = tag.display_name.presence || tag.name
      # コンテンツ中の #tag_name パターンをリンクに変換
      tag_url = "#{base_url}/tags/#{ERB::Util.url_encode(tag.name)}"
      link = %(<a href="#{tag_url}" class="mention hashtag" rel="tag">) +
             %(#<span>#{CGI.escapeHTML(display_name)}</span></a>)

      # display_nameでの検索（大文字小文字を区別）
      content = gsub_outside_a_tags(content, "##{display_name}", link) if content.include?("##{display_name}")

      # 正規化名でも検索（display_nameと異なる場合のみ）
      next unless tag.name != display_name.downcase && content.include?("##{tag.name}")

      content = gsub_outside_a_tags(content, "##{tag.name}", link)
    end

    content
  end

  # メンション置換を<a>タグの外側でのみ実行する（URL内のメンションパターンを破壊しない）
  def gsub_outside_a_tags(content, search_text, replacement)
    a_tag_ranges = []
    content.scan(/<a\b[^>]*>.*?<\/a>/mi) do
      a_tag_ranges << ($LAST_MATCH_INFO.begin(0)...$LAST_MATCH_INFO.end(0))
    end

    return content.gsub(search_text, replacement) if a_tag_ranges.empty?

    result = content.dup
    offset = 0
    search_re = Regexp.new(Regexp.escape(search_text))

    content.scan(search_re) do
      match_start = $LAST_MATCH_INFO.begin(0)
      match_end = $LAST_MATCH_INFO.end(0)

      inside_link = a_tag_ranges.any? { |range| match_start >= range.begin && match_end <= range.end }

      unless inside_link
        actual_start = match_start + offset
        actual_end = match_end + offset
        result[actual_start...actual_end] = replacement
        offset += replacement.length - search_text.length
      end
    end

    result
  end

  def apply_url_links_only(content)
    # 既存のHTMLタグ位置を記録
    tags = []
    content.scan(/<[^>]+>/) { |_match| tags << { start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) } }

    # 既存のaタグ全体の範囲を記録（タグ内テキストもリンク化対象外にする）
    a_tag_ranges = []
    content.scan(/<a\b[^>]*>.*?<\/a>/mi) do |_match|
      a_tag_ranges << { start: $LAST_MATCH_INFO.begin(0), end: $LAST_MATCH_INFO.end(0) }
    end

    # URLパターンを探してリンク化（ただし、既存のタグ内は除外）
    # www.で始まるURLもマッチ対象に含める
    url_pattern = /(https?:\/\/[^\s<>＜＞"']+|www\.[^\s<>＜＞"']+)/
    result = content.dup
    offset = 0

    content.scan(url_pattern) do |url|
      url_start = $LAST_MATCH_INFO.begin(0)
      url_end = $LAST_MATCH_INFO.end(0)

      # このURLが既存のHTMLタグ内にないかチェック
      inside_tag = tags.any? do |tag|
        url_start >= tag[:start] && url_end <= tag[:end]
      end

      # 既存のaタグの中（テキスト部分含む）にないかチェック
      inside_a_tag = a_tag_ranges.any? do |range|
        url_start >= range[:start] && url_end <= range[:end]
      end

      unless inside_tag || inside_a_tag
        # www.で始まる場合はhttps://を補完
        href = url[0].start_with?('www.') ? "https://#{url[0]}" : url[0]
        display_text = href.delete_prefix('https://')
        linked_url = %(<a href="#{href}" target="_blank" rel="noopener noreferrer" ) +
                     %(class="text-gray-500 hover:text-gray-700 transition-colors">#{display_text}</a>)

        # オフセットを考慮して置換
        actual_start = url_start + offset
        actual_end = url_end + offset
        result[actual_start...actual_end] = linked_url
        offset += linked_url.length - url[0].length
      end
    end

    result
  end

  def default_status_structure
    # エラー時のフォールバック構造
    {
      id: '0',
      created_at: Time.current.iso8601,
      edited_at: nil,
      uri: '',
      url: '',
      visibility: 'public',
      language: nil,
      sensitive: false,
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      replies_count: 0,
      reblogs_count: 0,
      favourites_count: 0,
      favourited: false,
      reblogged: false,
      bookmarked: false,
      pinned: false,
      quotes_count: 0,
      quoted: false,
      spoiler_text: '',
      content: '',
      account: {},
      reblog: nil,
      quote: nil,
      media_attachments: [],
      mentions: [],
      tags: [],
      emojis: [],
      card: nil,
      poll: nil
    }
  end
end
