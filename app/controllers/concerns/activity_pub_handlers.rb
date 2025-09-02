# frozen_string_literal: true

module ActivityPubHandlers
  extend ActiveSupport::Concern

  include ActivityPubFollowHandlers
  include ActivityPubInteractionHandlers

  private

  # Block Activity処理
  def handle_block_activity
    Rails.logger.info '🚫 Processing Block activity'

    return head :accepted unless @target_actor&.local?

    existing_block = Block.find_by(
      actor: @sender,
      target_actor: @target_actor
    )

    return head :accepted if existing_block

    # ブロック関係を作成
    Block.create!(
      actor: @sender,
      target_actor: @target_actor
    )

    # ブロックされた場合、既存のフォロー関係を削除
    remove_follow_relationships_for_block

    Rails.logger.info "🚫 Block created: #{@sender.ap_id} blocked #{@target_actor.ap_id}"
    head :accepted
  end

  def remove_follow_relationships_for_block
    # 双方向のフォロー関係を削除
    Follow.where(
      actor: @sender,
      target_actor: @target_actor
    ).destroy_all

    Follow.where(
      actor: @target_actor,
      target_actor: @sender
    ).destroy_all
  end
end
