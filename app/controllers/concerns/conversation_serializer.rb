# frozen_string_literal: true

module ConversationSerializer
  extend ActiveSupport::Concern
  include AccountSerializer
  include MediaSerializer

  def serialized_conversation(conversation)
    # participantsはコントローラーでincludesされているので、filterのみ行う
    other_participants = conversation.participants.reject { |p| p.id == current_user.id }

    {
      id: conversation.id.to_s,
      unread: conversation.unread,
      accounts: other_participants.map { |participant| serialized_account(participant) },
      last_status: conversation.last_status ? serialized_conversation_status(conversation.last_status) : nil
    }
  end

  private

  def serialized_conversation_status(status)
    {
      id: status.id.to_s,
      created_at: status.published_at.iso8601,
      in_reply_to_id: nil,
      in_reply_to_account_id: nil,
      sensitive: status.sensitive || false,
      spoiler_text: status.summary || '',
      visibility: 'direct',
      language: status.language || 'en',
      uri: status.ap_id,
      url: status.public_url,
      replies_count: 0,
      reblogs_count: 0,
      favourites_count: 0,
      content: status.content || '',
      reblog: nil,
      account: serialized_account(status.actor),
      media_attachments: serialized_media_attachments(status),
      mentions: serialized_mentions(status),
      tags: [],
      emojis: [],
      card: nil,
      poll: nil
    }
  end

  def serialized_mentions(status)
    # DMの場合、参加者全員がメンションとして扱われる
    status.conversation&.participants&.map do |participant|
      {
        id: participant.id.to_s,
        username: participant.username,
        url: participant.ap_id,
        acct: participant.acct
      }
    end || []
  end
end
