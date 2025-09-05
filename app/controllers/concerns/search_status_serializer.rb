# frozen_string_literal: true

module SearchStatusSerializer
  include PollSerializer
  include MediaSerializer
  include TextLinkingHelper
  include StatusSerializer

  def serialized_status(status)
    base_status_data(status).merge(
      additional_status_data(status)
    )
  end

  def serialized_media_attachments(status)
    status.media_attachments.map do |attachment|
      build_media_attachment_data(attachment)
    end
  end

  private

  def base_status_data(status)
    {
      id: status.id.to_s,
      created_at: status.published_at.iso8601,
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      sensitive: status.sensitive || false,
      spoiler_text: status.summary || '',
      visibility: status.visibility || 'public',
      language: 'ja',
      uri: status.ap_id,
      url: status.public_url
    }
  end

  def additional_status_data(status)
    {
      replies_count: 0,
      reblogs_count: 0,
      favourites_count: 0,
      reblogged: false,
      favourited: false,
      muted: false,
      bookmarked: false,
      pinned: false,
      content: parse_content_for_search(status),
      reblog: nil,
      application: nil,
      account: serialized_account(status.actor),
      media_attachments: serialized_media_attachments(status),
      mentions: [],
      tags: [],
      emojis: serialized_emojis(status),
      card: nil,
      poll: serialize_poll_for_search(status.poll)
    }
  end

  def build_media_attachment_data(attachment)
    {
      id: attachment.id.to_s,
      type: attachment.media_type,
      url: attachment.remote_url || attachment.url,
      preview_url: attachment.remote_url || attachment.url,
      remote_url: attachment.remote_url,
      description: attachment.description,
      blurhash: attachment.blurhash,
      meta: build_search_media_meta(attachment)
    }
  end

  def build_search_media_meta(attachment)
    # 検索用には original メタデータのみを返す（MediaSerializer の original 部分を使用）
    {
      original: build_original_meta(attachment)
    }
  end

  def parse_content_for_search(status)
    return '' if status.content.blank?

    content_with_shortcodes = parse_content_links_only(status.content)
    auto_link_urls(content_with_shortcodes)
  end
end
