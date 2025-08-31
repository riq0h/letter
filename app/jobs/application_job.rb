# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # デッドロックが発生したジョブを自動的に再試行
  retry_on ActiveRecord::Deadlocked, wait: 1.minute, attempts: 3

  # 基盤となるレコードが利用できない場合、ほとんどのジョブは無視しても安全
  discard_on ActiveJob::DeserializationError

  # デフォルトのリトライ設定（個別のジョブで上書き可能）
  retry_on StandardError, wait: 1.minute, attempts: 3

  private

  def handle_error(error, context_message = nil)
    message = context_message || "#{self.class.name} error"
    Rails.logger.error "💥 #{message}: #{error.message}"
    Rails.logger.error error.backtrace.first(3).join("\n")

    # Re-raise the error to trigger ActiveJob's built-in retry mechanism
    # instead of calling retry_job directly to avoid SolidQueue duplication
    raise error
  end
end
