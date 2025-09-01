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
      replies_count: replies_count(status),
      reblogs_count: status.reblogs_count || 0,
      favourites_count: status.favourites_count || 0,
      favourited: favourited_by_current_user?(status),
      reblogged: reblogged_by_current_user?(status),
      bookmarked: bookmarked_by_current_user?(status),
      pinned: pinned_by_current_user?(status),
      quotes_count: status.quotes_of_this.count,
      quoted: quoted_by_current_user?(status)
    }
  end

  def content_data(status)
    # 絵文字をショートコードに戻してからURLリンク化
    content_with_shortcodes = parse_content_links_only(status.content || '')
    linked_content = auto_link_urls(content_with_shortcodes)

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
    return nil if status.in_reply_to_ap_id.blank?

    in_reply_to = ActivityPubObject.find_by(ap_id: status.in_reply_to_ap_id)
    in_reply_to&.id&.to_s
  end

  def in_reply_to_account_id(status)
    return nil if status.in_reply_to_ap_id.blank?

    in_reply_to = ActivityPubObject.find_by(ap_id: status.in_reply_to_ap_id)
    return nil unless in_reply_to&.actor

    in_reply_to.actor.id.to_s
  end

  def replies_count(status)
    ActivityPubObject.where(in_reply_to_ap_id: status.ap_id).count
  end

  def favourited_by_current_user?(status)
    return false unless current_user

    current_user.favourites.exists?(object: status)
  end

  def reblogged_by_current_user?(status)
    return false unless current_user

    current_user.reblogs.exists?(object: status)
  end

  def bookmarked_by_current_user?(status)
    return false unless current_user

    current_user.bookmarks.exists?(object: status)
  end

  def pinned_by_current_user?(status)
    # AccountsController#statusesの場合は、そのアカウントが固定した投稿かどうかを返す
    return status.actor.pinned_statuses.exists?(object: status) if params[:controller] == 'api/v1/accounts' && params[:action] == 'statuses'

    # その他の場合は現在のユーザが固定した投稿かどうかを返す
    return false unless current_user

    current_user.pinned_statuses.exists?(object: status)
  end

  def quoted_by_current_user?(status)
    return false unless current_user

    current_user.quote_posts.exists?(quoted_object: status)
  end

  def build_quote_data(status)
    quote_post = status.quote_posts.first
    return nil unless quote_post

    quoted_actor = quote_post.quoted_object.actor
    {
      id: quote_post.quoted_object.id.to_s,
      created_at: quote_post.quoted_object.published_at&.iso8601,
      uri: quote_post.quoted_object.ap_id,
      url: quote_post.quoted_object.public_url,
      content: auto_link_urls(parse_content_links_only(quote_post.quoted_object.content || '')),
      account: {
        id: quoted_actor.id.to_s,
        username: quoted_actor.username,
        acct: quoted_actor.acct,
        display_name: quoted_actor.display_name || quoted_actor.username,
        avatar: quoted_actor.avatar_url
      },
      shallow_quote: quote_post.shallow_quote?
    }
  end

  def serialize_poll(status)
    return nil unless status.poll

    poll = status.poll
    result = poll.to_mastodon_api

    # 認証済みの場合は現在のユーザ固有データを追加
    if current_user
      # 一度のクエリで投票情報を取得
      user_votes = poll.poll_votes.where(actor: current_user)
      result[:voted] = user_votes.exists?
      result[:own_votes] = user_votes.pluck(:choice)
    end

    result
  end

  def serialize_preview_card(status)
    return nil if status.content.blank?

    # 投稿内容からURLを抽出
    urls = extract_urls_from_content(status.content)
    return nil if urls.empty?

    # 最初のURLのプレビューカードを取得
    preview_url = urls.first
    link_preview = LinkPreview.find_by(url: preview_url)
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
