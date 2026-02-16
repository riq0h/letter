# frozen_string_literal: true

module ScheduledStatusHandling
  extend ActiveSupport::Concern

  private

  def create_scheduled_status
    scheduled_at = parse_scheduled_at
    return render_validation_failed('Invalid scheduled_at format') unless scheduled_at

    scheduled_params = prepare_scheduled_params

    # statusパラメータの存在を確認
    return render_validation_failed('Status text is required') if scheduled_params['status'].blank?

    media_attachment_ids = params[:media_ids] || []

    scheduled_status = current_user.scheduled_statuses.build(
      scheduled_at: scheduled_at,
      params: scheduled_params,
      media_attachment_ids: media_attachment_ids
    )

    if scheduled_status.save
      render json: scheduled_status.to_mastodon_api, status: :created
    else
      render json: {
        error: scheduled_status.errors.full_messages.join(', ')
      }, status: :unprocessable_content
    end
  end

  def parse_scheduled_at
    Time.zone.parse(params[:scheduled_at])
  rescue ArgumentError, TypeError
    nil
  end

  def prepare_scheduled_params
    # 予約投稿パラメータ許可
    permitted = params.permit(:status, :text, :in_reply_to_id, :sensitive, :spoiler_text, :visibility, :language,
                              poll: [:expires_in, :multiple, :hide_totals, { options: [] }])

    base_params = permitted.to_h.compact

    # textパラメータがある場合はstatusにマップ
    base_params['status'] = base_params['text'] if base_params['text'].present? && base_params['status'].blank?

    # textパラメータは削除（statusを使用）
    base_params.delete('text')

    # visibilityのデフォルト値を確保
    base_params['visibility'] ||= 'public'

    base_params['poll'] = poll_params if poll_params.present?

    base_params
  end

  def poll_params
    return nil if params[:poll].blank?

    params.permit(poll: [:expires_in, :multiple, :hide_totals, { options: [] }])[:poll]
  end
end
