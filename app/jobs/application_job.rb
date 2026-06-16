# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # 一過性のSQLiteロック競合を各ジョブ内でその場リトライできるようにする
  include DatabaseLockRetryable

  # デッドロックが発生したジョブを自動的に再試行
  retry_on ActiveRecord::Deadlocked, wait: 1.minute, attempts: 3

  # 基盤となるレコードが利用できない場合、ほとんどのジョブは無視しても安全
  discard_on ActiveJob::DeserializationError

  # SolidQueueの重複制約エラーを避けるため、デフォルトのretry_onは使用しない
  # 個別のジョブで手動リトライ実装が必要

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
