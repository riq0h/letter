# frozen_string_literal: true

class Conversation < ApplicationRecord
  # === アソシエーション ===
  has_many :conversation_participants, dependent: :destroy
  has_many :participants, through: :conversation_participants, source: :actor
  belongs_to :last_status, class_name: 'ActivityPubObject', optional: true

  # === バリデーション ===
  validates :unread, inclusion: { in: [true, false] }

  # === スコープ ===
  scope :unread, -> { where(unread: true) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :for_actor, ->(actor) { joins(:conversation_participants).where(conversation_participants: { actor: actor }) }

  # === インスタンスメソッド ===

  def mark_as_read!
    update!(unread: false)
  end

  def mark_as_unread!
    update!(unread: true)
  end

  def update_last_status!(status)
    update!(
      last_status: status,
      unread: true,
      updated_at: Time.current
    )
  end

  def other_participants(current_actor)
    participants.where.not(id: current_actor.id)
  end

  def includes_actor?(actor)
    participants.include?(actor)
  end

  # === クラスメソッド ===

  def self.find_or_create_for_actors(actors)
    # 同じ参加者セットを持つ会話を検索
    actor_ids = actors.map(&:id).sort

    existing_conversation = joins(:conversation_participants)
                            .group('conversations.id')
                            .having('COUNT(conversation_participants.actor_id) = ? AND GROUP_CONCAT(conversation_participants.actor_id ORDER BY conversation_participants.actor_id) = ?',
                                    actor_ids.size, actor_ids.join(','))
                            .first

    return existing_conversation if existing_conversation

    # 新しい会話を作成
    transaction do
      conversation = create!(unread: false)
      actors.each do |actor|
        conversation.conversation_participants.create!(actor: actor)
      end
      conversation
    end
  rescue ActiveRecord::RecordNotUnique
    # 競合状態で既に作成されていた場合は再検索
    joins(:conversation_participants)
      .group('conversations.id')
      .having('COUNT(conversation_participants.actor_id) = ? AND GROUP_CONCAT(conversation_participants.actor_id ORDER BY conversation_participants.actor_id) = ?',
              actor_ids.size, actor_ids.join(','))
      .first
  end
end
