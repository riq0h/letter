# frozen_string_literal: true

# スケジュール済みステータスの公開処理を統括するOrganizer
# ステータス作成、メディア添付、投票作成、スケジュール削除を段階的に実行
class PublishScheduledStatusOrganizer
  class Result < OrganizerResult
    attr_reader :status

    def initialize(success:, status: nil, error: nil)
      @status = status
      super(success: success, error: error)
    end
  end

  def self.call(scheduled_status)
    new(scheduled_status).call
  end

  def initialize(scheduled_status)
    @scheduled_status = scheduled_status
    @actor = scheduled_status.actor
  end

  # スケジュール済みステータスを公開
  def call
    Rails.logger.info "📅 Publishing scheduled status #{@scheduled_status.id} for #{@actor.username}"

    ActiveRecord::Base.transaction do
      # ステータス作成
      status = create_status
      return failure('Failed to create status') unless status

      # メディア添付処理
      attach_media_to_status(status) if @scheduled_status.media_attachment_ids.present?

      # 投票作成処理
      create_poll_for_status(status) if poll_params.present?

      record_quote(status)

      # スケジュール済みステータスを削除
      @scheduled_status.destroy!

      HomeFeedManager.add_status(status)

      Rails.logger.info "✅ Scheduled status #{@scheduled_status.id} published as status #{status.id}"
      success(status)
    end
  rescue StandardError => e
    Rails.logger.error "❌ Failed to publish scheduled status: #{e.message}"
    failure(e.message)
  end

  private

  attr_reader :scheduled_status, :actor

  def success(status)
    Result.new(success: true, status: status)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  # ステータス作成処理
  def create_status
    status_params = prepare_status_params

    @actor.objects.create!(
      object_type: 'Note',
      content: status_params[:status],
      visibility: status_params[:visibility] || 'public',
      sensitive: status_params[:sensitive] || false,
      summary: status_params[:spoiler_text],
      in_reply_to_ap_id: reply_target_ap_id(status_params[:in_reply_to_id]),
      published_at: Time.current,
      local: true,
      ap_id: generate_ap_id,
      quote_policy: QuotePolicy.setting_for(status_params[:visibility] || 'public', requested_quote_policy(status_params))
    )
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create status: #{e.message}"
    # 元のエラーメッセージを再発生させる
    raise e
  end

  # ステータスパラメータの準備
  def prepare_status_params
    base_params = @scheduled_status.params.dup

    # 適切なデフォルト値を確保
    base_params['visibility'] ||= 'public'
    base_params['sensitive'] ||= false

    base_params.symbolize_keys
  end

  # ActivityPub IDの生成
  def generate_ap_id
    ApIdGeneration.generate_ap_id
  end

  # メディア添付処理
  def attach_media_to_status(status)
    return unless @scheduled_status.media_attachment_ids.is_a?(Array)

    media_attachments = MediaAttachment.where(
      id: @scheduled_status.media_attachment_ids,
      actor: @actor
    )

    media_attachments.update_all(object_id: status.id)
    Rails.logger.info "📎 Attached #{media_attachments.count} media files to status #{status.id}"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to attach media: #{e.message}"
  end

  # 投票作成処理
  def create_poll_for_status(status)
    symbolized_params = poll_params.deep_symbolize_keys

    PollCreationService.create_for_status(status, symbolized_params)
    Rails.logger.info "📊 Created poll for status #{status.id}"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create poll: #{e.message}"
  end

  # 予約時のin_reply_to_idは投稿のID(Mastodon API)なので、返信先の投稿のURIにして保存する
  def reply_target_ap_id(in_reply_to_id)
    return if in_reply_to_id.blank?
    return in_reply_to_id if in_reply_to_id.to_s.start_with?('http')

    ActivityPubObject.find_by(id: in_reply_to_id)&.ap_id
  end

  def requested_quote_policy(status_params)
    status_params[:quote_approval_policy].presence || @actor.setting('posting:default:quote_policy')
  end

  # 予約時に指定された投稿を引用する。引用元が消えていれば引用なしで公開する
  def record_quote(status)
    quoted_id = @scheduled_status.params['quoted_status_id']
    return if quoted_id.blank?

    quoted = ActivityPubObject.find_by(id: quoted_id)
    QuotePost.record!(status, quoted) if quoted
  end

  # 投票パラメータの取得
  def poll_params
    @scheduled_status.params['poll']
  end
end
