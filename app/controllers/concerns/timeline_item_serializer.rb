# frozen_string_literal: true

# タイムラインの1件(投稿かブースト)をMastodonのStatusの形にする
module TimelineItemSerializer
  extend ActiveSupport::Concern

  included do
    include StatusSerializationHelper
  end

  private

  def serialize_timeline_item(item)
    case item
    when Reblog
      # リブログ - リブログされた元投稿をラップして返す
      reblogged_status = serialized_status(item.object)
      reblogged_status[:reblog] = nil # ネストしたリブログを防ぐ

      # リブログ情報を追加
      {
        id: item.timeline_id,
        created_at: item.created_at.iso8601,
        account: serialized_account(item.actor),
        reblog: reblogged_status
      }.merge(default_interaction_data)
    else
      # 通常のステータスまたはActivityPubObject
      serialized_status(item)
    end
  end

  def default_interaction_data
    {
      favourited: false,
      reblogged: false,
      muted: false,
      bookmarked: false,
      pinned: false,
      content: '',
      visibility: 'public',
      sensitive: false,
      spoiler_text: '',
      url: '',
      uri: '',
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      media_attachments: [],
      mentions: [],
      tags: [],
      emojis: [],
      reblogs_count: 0,
      favourites_count: 0,
      replies_count: 0,
      language: nil,
      text: nil,
      edited_at: nil,
      poll: nil,
      card: nil,
      quote: nil
    }
  end
end
