# frozen_string_literal: true

class Block < ApplicationRecord
  belongs_to :actor, class_name: 'Actor'
  belongs_to :target_actor, class_name: 'Actor'

  validates :actor_id, uniqueness: { scope: :target_actor_id }
  validate :cannot_block_self

  # コールバック
  before_validation :set_defaults, on: :create
  after_create :send_block_activity, if: :should_send_block_activity?
  after_destroy :send_unblock_activity, if: :should_send_unblock_activity?

  def local_block?
    actor.local?
  end

  def remote_block?
    !actor.local?
  end

  def unblock!
    destroy
  end

  private

  def cannot_block_self
    errors.add(:target_actor, 'cannot block yourself') if actor_id == target_actor_id
  end

  def set_defaults
    # 必要に応じてデフォルト値を設定
  end

  def should_send_block_activity?
    # ローカルユーザが外部ユーザをブロックする場合のみ送信
    actor&.local? && target_actor && !target_actor.local?
  end

  def should_send_unblock_activity?
    # 削除前の状態を保存
    @actor_was_local = actor&.local?
    @target_actor_was_remote = target_actor && !target_actor.local?

    # ローカルユーザが外部ユーザのブロックを解除する場合のみ送信
    @actor_was_local && @target_actor_was_remote
  end

  def send_block_activity
    Rails.logger.info "📤 Creating Block activity for block #{id}"

    SendBlockJob.perform_later(self)
  end

  def send_unblock_activity
    Rails.logger.info '📤 Creating Undo Block activity for unblock'

    # 削除前の情報を使用してUndo活動を送信
    SendUnblockJob.perform_later(
      actor.ap_id,
      target_actor.ap_id,
      target_actor.inbox_url
    )
  end
end
