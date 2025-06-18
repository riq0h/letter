# frozen_string_literal: true

class InboxController < ApplicationController
  include ActivityPubVerification
  include ActivityPubHandlers
  include ActivityPubObjectHandlers
  include ActivityPubCreateHandlers

  # CSRFトークン無効化（外部からのPOST）
  skip_before_action :verify_authenticity_token

  # Content-Type検証
  before_action :verify_content_type
  before_action :find_target_actor
  before_action :parse_activity_json
  before_action :verify_http_signature
  before_action :find_or_create_sender
  before_action :check_if_sender_blocked

  def create
    Rails.logger.info "📥 Inbox: Received #{@activity['type']} from #{@sender&.ap_id}"

    process_activity
  rescue StandardError => e
    handle_general_error(e)
  end

  private

  def process_activity
    case @activity['type']
    when 'Follow'
      handle_follow_activity
    when 'Accept'
      handle_accept_activity
    when 'Reject'
      handle_reject_activity
    when 'Undo'
      handle_undo_activity
    when 'Create'
      handle_create_activity
    when 'Update'
      handle_update_activity
    when 'Delete'
      handle_delete_activity
    when 'Announce'
      handle_announce_activity
    when 'Like'
      handle_like_activity
    else
      handle_unsupported_activity
    end
  end

  def handle_unsupported_activity
    Rails.logger.warn "⚠️ Unsupported activity type: #{@activity['type']}"
    head :accepted # ActivityPubでは未対応でも202を返す
  end

  def handle_validation_error(error)
    Rails.logger.error "❌ ActivityPub validation error: #{error.message}"
    render json: { error: error.message }, status: :bad_request
  end

  def handle_signature_error(error)
    Rails.logger.error "🔒 HTTP Signature error: #{error.message}"
    render json: { error: 'Invalid signature' }, status: :unauthorized
  end

  def check_if_sender_blocked
    return unless should_check_blocking?

    handle_actor_blocking if actor_blocked?
    handle_domain_blocking if domain_blocked?
  end

  def should_check_blocking?
    @target_actor&.local? && @sender
  end

  def actor_blocked?
    @target_actor.blocking?(@sender)
  end

  def domain_blocked?
    @sender.domain && @target_actor.domain_blocking?(@sender.domain)
  end

  def handle_actor_blocking
    log_blocked_activity('Blocked actor')
    head :forbidden
  end

  def handle_domain_blocking
    log_blocked_activity('Domain blocked actor', "(#{@sender.domain})")
    head :forbidden
  end

  def log_blocked_activity(prefix, suffix = '')
    Rails.logger.info "🚫 #{prefix} #{@sender.ap_id} #{suffix} tried to send #{@activity['type']} to #{@target_actor.ap_id}"
  end

  def handle_general_error(error)
    Rails.logger.error "💥 Inbox processing error: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    head :internal_server_error
  end
end
