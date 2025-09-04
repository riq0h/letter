# frozen_string_literal: true

module ActivityPubFollowHandlers
  extend ActiveSupport::Concern

  private

  # Follow Activity処理
  def handle_follow_activity
    Rails.logger.info '👥 Processing Follow request'

    existing_follow = find_existing_follow

    if existing_follow
      if existing_follow.accepted?
        Rails.logger.warn '⚠️ Follow already accepted'
      else
        # 未承認のフォローを自動承認
        Rails.logger.info '🔄 Re-accepting pending follow'
        existing_follow.accept!

        # 再承認時にも通知を作成
        Notification.create_follow_notification(existing_follow)

        Rails.logger.info "✅ Follow re-accepted: #{existing_follow.id}"
      end
      head :accepted
      return
    end

    create_follow_request
  end

  def find_existing_follow
    Follow.find_by(
      actor: @sender,
      target_actor: @target_actor
    )
  end

  def create_follow_request
    follow = Follow.create!(
      actor: @sender,
      target_actor: @target_actor,
      ap_id: @activity['id'],
      follow_activity_ap_id: @activity['id']
    )

    # 外部フォローの場合は明示的にAccept activityを送信
    if @target_actor.local? && !@sender.local?
      Rails.logger.info '🎯 External follow received, creating Accept activity'
      follow.create_accept_activity
    end

    # フォロー通知を作成
    Notification.create_follow_notification(follow)

    Rails.logger.info "✅ Follow auto-accepted: #{follow.id}"
    head :accepted
  end

  # Accept Activity処理
  def handle_accept_activity
    Rails.logger.info '✅ Processing Accept activity'

    object = @activity['object']
    follow_ap_id = extract_activity_id(object)

    # 通常のフォロー関係の Accept を確認
    follow = Follow.find_by(follow_activity_ap_id: follow_ap_id)

    if follow
      follow.update!(accepted: true)
      Rails.logger.info "✅ Follow accepted: #{follow.id}"
    else
      # リレーフォローの Accept を確認
      relay = Relay.find_by(follow_activity_id: follow_ap_id)
      if relay
        relay.update!(state: 'accepted', last_error: nil, delivery_attempts: 0)
        Rails.logger.info "✅ Relay follow accepted: #{relay.inbox_url}"
      else
        Rails.logger.warn "⚠️ Follow/Relay not found for Accept: #{follow_ap_id}"
      end
    end

    head :accepted
  end

  # Reject Activity処理
  def handle_reject_activity
    Rails.logger.info '❌ Processing Reject activity'

    object = @activity['object']
    follow_ap_id = extract_activity_id(object)

    # 通常のフォロー関係の Reject を確認
    follow = Follow.find_by(follow_activity_ap_id: follow_ap_id)

    if follow
      follow.destroy!
      Rails.logger.info "❌ Follow rejected and deleted: #{follow_ap_id}"
    else
      # リレーフォローの Reject を確認
      relay = Relay.find_by(follow_activity_id: follow_ap_id)
      if relay
        relay.update!(
          state: 'rejected',
          last_error: 'Follow request rejected by relay',
          follow_activity_id: nil,
          followed_at: nil
        )
        Rails.logger.info "❌ Relay follow rejected: #{relay.inbox_url}"
      else
        Rails.logger.warn "⚠️ Follow/Relay not found for Reject: #{follow_ap_id}"
      end
    end

    head :accepted
  end

  # Undo Activity処理
  def handle_undo_activity
    Rails.logger.info '↩️ Processing Undo activity'

    object = @activity['object']

    case object['type']
    when 'Follow'
      handle_undo_follow(object)
    when 'Block'
      handle_undo_block(object)
    when 'Like'
      handle_undo_like(object)
    when 'Announce'
      handle_undo_announce(object)
    else
      Rails.logger.warn "⚠️ Unsupported Undo object: #{object['type']}"
    end

    head :accepted
  end

  def handle_undo_follow(object)
    # まず正確なIDマッチを試行
    follow = Follow.find_by(
      actor: @sender,
      target_actor: @target_actor,
      follow_activity_ap_id: object['id']
    )

    # IDが一致しない場合は、同じアクター間の最新のフォローを検索
    unless follow
      Rails.logger.info "↩️ Exact ID not found, searching for any follow from #{@sender.ap_id}"
      follow = Follow.find_by(
        actor: @sender,
        target_actor: @target_actor
      )
    end

    return unless follow

    follow.destroy!
    Rails.logger.info "↩️ Follow undone: #{follow.id} (requested: #{object['id']})"
  end

  def handle_undo_block(_object)
    # ブロック関係を検索して削除
    block = Block.find_by(
      actor: @sender,
      target_actor: @target_actor
    )

    return unless block

    block.destroy!
    Rails.logger.info "🔓 Block undone: #{@sender.ap_id} unblocked #{@target_actor.ap_id}"
  end

  def handle_undo_like(object)
    Rails.logger.info '💔 Processing Undo Like activity'

    # Like objectのオブジェクトIDを取得
    liked_object_id = extract_like_object_id_from_undo(object)
    return unless liked_object_id

    # 対象オブジェクトを検索
    target_object = ActivityPubObject.find_by(ap_id: liked_object_id)
    return unless target_object

    # Favouriteレコードを検索して削除
    favourite = Favourite.find_by(actor: @sender, object: target_object)
    if favourite
      favourite.destroy!
      Rails.logger.info "💔 Like undone: removed favourite #{favourite.id} for object #{target_object.ap_id}"
    end

    # Activityレコードも削除（あれば）
    activity = target_object.activities.find_by(actor: @sender, activity_type: 'Like')
    return unless activity

    activity.destroy!
    Rails.logger.info "💔 Like activity removed: #{activity.id}"
  end

  def handle_undo_announce(object)
    Rails.logger.info '🔄 Processing Undo Announce activity'

    # Announce objectのオブジェクトIDを取得
    announced_object_id = extract_announce_object_id_from_undo(object)
    return unless announced_object_id

    # 対象オブジェクトを検索
    target_object = ActivityPubObject.find_by(ap_id: announced_object_id)
    return unless target_object

    # Reblogレコードを検索して削除
    reblog = Reblog.find_by(actor: @sender, object: target_object)
    if reblog
      reblog.destroy!
      Rails.logger.info "🔄 Announce undone: removed reblog #{reblog.id} for object #{target_object.ap_id}"
    end

    # Activityレコードも削除（あれば）
    activity = target_object.activities.find_by(actor: @sender, activity_type: 'Announce')
    return unless activity

    activity.destroy!
    Rails.logger.info "🔄 Announce activity removed: #{activity.id}"
  end

  def extract_activity_id(object)
    object.is_a?(Hash) ? object['id'] : object
  end

  def extract_like_object_id_from_undo(like_object)
    # Undo.Like活動のobjectフィールドから対象のオブジェクトIDを抽出
    object = like_object['object']
    object.is_a?(Hash) ? object['id'] : object
  end

  def extract_announce_object_id_from_undo(announce_object)
    # Undo.Announce活動のobjectフィールドから対象のオブジェクトIDを抽出
    object = announce_object['object']
    object.is_a?(Hash) ? object['id'] : object
  end
end
