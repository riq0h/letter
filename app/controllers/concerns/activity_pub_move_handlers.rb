# frozen_string_literal: true

module ActivityPubMoveHandlers
  extend ActiveSupport::Concern

  private

  # アカウントの引っ越し(Move)。送信者自身の引っ越しだけを受け付け、引っ越し先の確認と
  # フォローの付け替えは、相手のサーバへの問い合わせが要るのでジョブで行う
  def handle_move_activity
    moved = ActivityPubOrigin.value_or_id(@activity['object'])
    target = ActivityPubOrigin.value_or_id(@activity['target'])

    if moved == @sender.ap_id && target.present? && !@sender.local?
      ProcessAccountMoveJob.perform_later(@sender.id, target)
    else
      Rails.logger.warn "🚚 Ignored Move from #{@sender.ap_id} for #{moved.inspect}"
    end
    head :accepted
  end
end
