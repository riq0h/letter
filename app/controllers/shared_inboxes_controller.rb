# frozen_string_literal: true

class SharedInboxesController < ApplicationController
  include ActivityPubVerification
  include ForwardedActivityHandling
  include ActivityPubHandlers
  include ActivityPubObjectHandlers
  include ActivityPubFollowHandlers
  include ActivityPubCollectionHandlers
  include RelayActivityHandling
  include ErrorResponseHelper

  # エラーハンドリング
  rescue_from ActivityPub::SignatureError, with: :handle_signature_error
  rescue_from ActivityPub::ValidationError, with: :handle_validation_error

  # CSRFトークン無効化（外部からのPOST）
  skip_before_action :verify_authenticity_token

  # Content-Type検証
  before_action :verify_content_type
  before_action :parse_activity_json
  before_action :skip_unknown_actor_activity
  before_action :verify_http_signature
  before_action :find_or_create_sender
  before_action :find_target_actor

  def create
    return handle_forwarded_activity if forwarded_activity?
    return handle_relay_activity if sending_relay

    handle_regular_activity
  rescue StandardError => e
    handle_general_error(e)
  end

  private

  def find_target_actor
    # Follow/Accept/Reject/Block活動の場合、対象アクターを特定
    case @activity['type']
    when 'Follow', 'Accept', 'Reject', 'Block'
      target_uri = extract_target_actor_uri
      @target_actor = Actor.find_by(ap_id: target_uri) if target_uri
    end
  end

  def extract_target_actor_uri
    case @activity['type']
    when 'Follow', 'Block'
      @activity['object']
    when 'Accept', 'Reject'
      # Accept/Rejectの場合、objectの中のFollowのobjectが対象アクター
      follow_activity = @activity['object']
      follow_activity.is_a?(Hash) ? follow_activity['object'] : nil
    end
  end

  def handle_regular_activity
    # ドメインブロックチェック（ターゲットが特定できている場合）
    if @target_actor&.local? && @sender
      if @target_actor.blocking?(@sender)
        Rails.logger.info "🚫 Blocked actor #{@sender.ap_id} tried to send #{@activity['type']} via shared inbox"
        head :forbidden
        return
      end
      if @sender.domain && @target_actor.domain_blocking?(@sender.domain)
        Rails.logger.info "🚫 Domain blocked actor #{@sender.ap_id} (#{@sender.domain}) tried to send #{@activity['type']} via shared inbox"
        head :forbidden
        return
      end
    end

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
    when 'Like', 'EmojiReact'
      # EmojiReact(Pleroma/Akkoma系)はLikeと同様に処理する(reaction付きふぁぼ)
      handle_like_activity
    when 'Follow'
      handle_follow_activity
    when 'Block'
      handle_block_activity
    when 'Undo'
      handle_undo_activity
    when 'Accept'
      handle_accept_activity
    when 'Reject'
      handle_reject_activity
    when 'Add'
      handle_add_activity
    when 'Remove'
      handle_remove_activity
    when 'QuoteRequest'
      handle_quote_request_activity
    when 'Move'
      handle_move_activity
    else
      Rails.logger.warn "⚠️ Unsupported activity type: #{@activity['type']}"
      head :accepted
    end
  end

  def handle_create_activity_with_organizer
    return handle_referenced_create if referenced_create?

    result = CreateActivityOrganizer.call(@activity, @sender)

    Rails.logger.error "Create activity failed: #{result.error}" unless result.success?
    # アバター未取り込みの送信者は先回りで到達確認(ジョブ・24hに1回)
    @sender&.enqueue_avatar_prefetch if result.success?
    head :accepted
  end

  def handle_signature_error(error)
    actor_uri = @activity&.dig('actor') || 'unknown'
    Rails.logger.warn "🔐 HTTP signature verification failed for #{actor_uri}: #{error.message}"
    render json: { error: 'Signature verification failed' }, status: :unauthorized
  end

  def handle_validation_error(error)
    Rails.logger.warn "❌ Validation error: #{error.message}"
    render json: { error: error.message }, status: :unprocessable_content
  end
end
