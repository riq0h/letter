# frozen_string_literal: true

# スケジュール済みステータスの公開処理を統括するOrganizer
# ステータス作成、メディア添付、投票作成、スケジュール削除を段階的に実行
class PublishScheduledStatusOrganizer
  class Result
    attr_reader :success, :status, :error

    def initialize(success:, status: nil, error: nil)
      @success = success
      @status = status
      @error = error
      freeze
    end

    def success?
      success
    end

    def failure?
      !success
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

      # スケジュール済みステータスを削除
      @scheduled_status.destroy!

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
      in_reply_to_ap_id: status_params[:in_reply_to_id],
      published_at: Time.current,
      local: true,
      ap_id: generate_ap_id
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
    base_url = Rails.application.config.activitypub.base_url
    "#{base_url}/users/#{@actor.username}/statuses/#{SecureRandom.hex(8)}"
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

  # 投票パラメータの取得
  def poll_params
    @scheduled_status.params['poll']
  end
end
