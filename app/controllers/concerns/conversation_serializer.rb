# frozen_string_literal: true

module ConversationSerializer
  extend ActiveSupport::Concern

  included do
    include StatusSerializationHelper
  end

  def serialized_conversation(conversation)
    # participantsはコントローラーでincludesされているので、filterのみ行う
    other_participants = conversation.participants.reject { |p| p.id == current_user.id }

    {
      id: conversation.id.to_s,
      unread: conversation.unread,
      accounts: other_participants.map { |participant| serialized_account(participant) },
      last_status: conversation.last_status ? serialized_status(conversation.last_status) : nil
    }
  end
end
