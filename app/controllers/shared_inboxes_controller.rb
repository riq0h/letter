# frozen_string_literal: true

class SharedInboxesController < ApplicationController
  include ActivityPubVerification
  include ActivityPubHandlers
  include ActivityPubObjectHandlers
  include ActivityPubFollowHandlers
  include GeneralErrorHandler

  # CSRFトークン無効化（外部からのPOST）
  skip_before_action :verify_authenticity_token

  # Content-Type検証
  before_action :verify_content_type
  before_action :parse_activity_json
  before_action :verify_http_signature
  before_action :find_or_create_sender
  before_action :find_target_actor
  before_action :check_if_relay_activity

  def create
    if @is_relay_activity
      handle_relay_activity
    else
      handle_regular_activity
    end
  rescue StandardError => e
    handle_general_error(e)
  end

  private

  def find_target_actor
    # Follow/Accept/Reject活動の場合、対象アクターを特定
    case @activity['type']
    when 'Follow', 'Accept', 'Reject'
      target_uri = extract_target_actor_uri
      @target_actor = Actor.find_by(ap_id: target_uri) if target_uri
    end
  end

  def extract_target_actor_uri
    case @activity['type']
    when 'Follow'
      @activity['object']
    when 'Accept', 'Reject'
      # Accept/Rejectの場合、objectの中のFollowのobjectが対象アクター
      follow_activity = @activity['object']
      follow_activity.is_a?(Hash) ? follow_activity['object'] : nil
    end
  end

  def check_if_relay_activity
    @is_relay_activity = relay_activity?

    return unless @is_relay_activity

    # リレーアクターのURIとマッチするリレーを探す（accepted・pending両方を対象）
    @relay = (Relay.accepted.to_a + Relay.pending.to_a).find do |r|
      # 1. 直接リレーサーバからの活動の場合
      next true if r.actor_uri == @activity['actor']

      # 2. HTTP SignatureのkeyIdでリレーを判定
      signature_header = request.headers['Signature']
      next false unless signature_header

      key_id = extract_key_id_from_signature(signature_header)
      next false unless key_id

      strict_relay_keyid_check(key_id, r)
    end
  end

  def handle_relay_activity
    case @activity['type']
    when 'Accept'
      handle_relay_accept
    when 'Reject'
      handle_relay_reject
    when 'Announce'
      handle_relay_announce
    when 'Create'
      handle_relay_create
    when 'Undo'
      handle_relay_undo
    else
      Rails.logger.warn "⚠️ Unsupported relay activity type: #{@activity['type']}"
      head :accepted
    end
  end

  def handle_regular_activity
    # 通常のActivityPub活動処理（既存のInboxControllerと同様）
    case @activity['type']
    when 'Create'
      handle_create_activity_with_organizer
    when 'Update'
      handle_update_activity
    when 'Delete'
      handle_delete_activity
    when 'Announce'
      handle_announce_activity
    when 'Like'
      handle_like_activity
    when 'Follow'
      handle_follow_activity
    when 'Undo'
      handle_undo_activity
    when 'Accept'
      handle_accept_activity
    when 'Reject'
      handle_reject_activity
    else
      Rails.logger.warn "⚠️ Unsupported activity type: #{@activity['type']}"
      head :accepted
    end
  end

  def handle_create_activity_with_organizer
    result = CreateActivityOrganizer.call(@activity, @sender, preserve_relay_info: @preserve_relay_info)

    Rails.logger.error "Create activity failed: #{result.error}" unless result.success?
    head :accepted
  end

  def handle_relay_accept
    return head :bad_request unless @relay

    # Follow要求が受け入れられた
    if @activity['object'] == @relay.follow_activity_id
      @relay.update!(
        state: 'accepted',
        last_error: nil,
        delivery_attempts: 0
      )
    end

    head :accepted
  end

  def handle_relay_reject
    return head :bad_request unless @relay

    # Follow要求が拒否された
    if @activity['object'] == @relay.follow_activity_id
      @relay.update!(
        state: 'rejected',
        last_error: 'Follow request rejected by relay',
        follow_activity_id: nil,
        followed_at: nil
      )
    end

    head :accepted
  end

  def handle_relay_announce
    return head :bad_request unless @relay

    # リレーからのAnnounce（投稿の再配信）を処理
    object_id = @activity['object']
    return head :bad_request unless object_id.is_a?(String)

    # リレーが実際に投稿を送信している場合、自動的にaccepted状態に更新
    if @relay.pending?
      @relay.update!(
        state: 'accepted',
        last_error: nil,
        delivery_attempts: 0
      )
      Rails.logger.info "Relay #{@relay.domain} automatically accepted due to active announcement"
    end

    # 既に処理済みかチェック
    existing_object = ActivityPubObject.find_by(ap_id: object_id)
    return head :accepted if existing_object

    # 元の投稿を取得して処理
    RelayAnnounceProcessorJob.perform_later(@activity, @relay.id)

    head :accepted
  end

  def handle_relay_create
    return head :bad_request unless @relay

    # リレー状態管理のみ行って、処理は既存フローに任せる
    @relay.update!(state: 'accepted', last_error: nil) if @relay.pending?

    # リレー情報を保持したまま通常処理へ
    @preserve_relay_info = @relay
    @is_relay_activity = false
    handle_regular_activity
  end

  def handle_relay_undo
    return head :bad_request unless @relay

    # リレーからのUndo処理（通常はフォロー解除）
    head :accepted
  end
end
