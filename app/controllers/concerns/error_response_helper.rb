# frozen_string_literal: true

module ErrorResponseHelper
  extend ActiveSupport::Concern

  private

  # 標準的なエラーレスポンス
  def render_error(message, status = :unprocessable_content)
    render json: { error: message }, status: status
  end

  # 認証が必要
  def render_authentication_required
    render json: { error: 'This action requires authentication' }, status: :unauthorized
  end

  # レコードが見つからない
  def render_not_found(resource = 'Record')
    render json: { error: "#{resource} not found" }, status: :not_found
  end

  # 認可されていない
  def render_not_authorized
    render json: { error: 'Not authorized' }, status: :forbidden
  end

  # 管理者権限が必要
  def render_admin_required
    render json: { error: 'Admin access required' }, status: :forbidden
  end

  # バリデーション失敗
  def render_validation_failed(message = 'Validation failed')
    render json: { error: message }, status: :unprocessable_content
  end

  # レート制限
  def render_rate_limited
    render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
  end

  # letter未実装機能
  def render_not_implemented(feature = 'Feature')
    render json: { error: "#{feature} not available in letter" }, status: :unprocessable_entity
  end

  # ローカルユーザ限定
  def render_local_only
    render json: { error: 'This method is only available to local users' }, status: :unprocessable_content
  end

  # 操作失敗
  def render_operation_failed(operation = 'Operation')
    render json: { error: "#{operation} failed" }, status: :unprocessable_entity
  end

  # 詳細付きバリデーション失敗
  def render_validation_failed_with_details(message, details)
    render json: { error: message, details: details }, status: :unprocessable_entity
  end

  # 自己操作禁止
  def render_self_action_forbidden(action)
    render json: { error: "Cannot #{action} yourself" }, status: :unprocessable_entity
  end

  # 必須パラメータ不足
  def render_missing_parameter(parameter)
    render json: { error: "#{parameter} parameter is required" }, status: :unprocessable_entity
  end

  # 権限不足
  def render_insufficient_permission(action)
    render json: { error: "You can only #{action}" }, status: :unprocessable_entity
  end

  # 制限超過
  def render_limit_exceeded(limit_type)
    render json: { error: "You have already #{limit_type} the maximum number" }, status: :unprocessable_entity
  end

  # 無効なアクション
  def render_invalid_action(reason)
    render json: { error: reason }, status: :unprocessable_entity
  end

  # モデルバリデーションエラー（オブジェクトのerrorsを返す）
  def render_validation_error(object_or_message = nil)
    case object_or_message
    when String
      render json: { error: object_or_message }, status: :unprocessable_entity
    when nil
      render json: { error: 'Validation failed', details: current_user.errors.full_messages }, status: :unprocessable_entity
    else
      render json: { error: 'Validation failed', details: object_or_message.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # 汎用エラーハンドリング（JSONレスポンス付き）
  def handle_general_error(error, context = nil)
    log_prefix = context || self.class.name.demodulize.downcase.gsub('controller', '')
    Rails.logger.error "#{log_prefix.capitalize} processing error: #{error.message}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end
end
