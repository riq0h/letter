# frozen_string_literal: true

# 投票期限チェックの定期実行設定
Rails.application.configure do
  config.after_initialize do
    # Solid Queueが利用可能で、本番環境またはテスト環境の場合
    if defined?(SolidQueue) && (Rails.env.production? || Rails.env.development?)
      begin
        # PollExpirationJobを10分後にスケジュール
        schedule_next_poll_expiration_job
        Rails.logger.info "🗳️  Poll expiration job scheduled"
      rescue => e
        Rails.logger.warn "Failed to schedule poll expiration job: #{e.message}"
      end
    end
  end

  # 次のPollExpirationJobをスケジュールするメソッド
  def schedule_next_poll_expiration_job
    # 既にスケジュールされているPollExpirationJobがあるかチェック
    existing_scheduled = SolidQueue::Job
                        .where(class_name: 'PollExpirationJob')
                        .where('scheduled_at > ?', Time.current)
                        .exists?

    unless existing_scheduled
      # 10分後にPollExpirationJobを実行
      PollExpirationJob.set(wait: 10.minutes).perform_later
      Rails.logger.debug "🗳️  Next poll expiration job scheduled for #{10.minutes.from_now}"
    end
  end
end

# グローバルにアクセス可能なスケジューラーメソッドを定義
def schedule_next_poll_expiration_job
  return unless defined?(SolidQueue)

  existing_scheduled = SolidQueue::Job
                      .where(class_name: 'PollExpirationJob')
                      .where('scheduled_at > ?', Time.current)
                      .exists?

  unless existing_scheduled
    PollExpirationJob.set(wait: 10.minutes).perform_later
    Rails.logger.debug "🗳️  Next poll expiration job scheduled for #{10.minutes.from_now}"
  end
rescue StandardError => e
  Rails.logger.error "Failed to schedule next poll expiration job: #{e.message}"
end