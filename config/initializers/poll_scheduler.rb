# frozen_string_literal: true

# 投票期限チェックの定期実行設定
Rails.application.configure do
  # 開発環境と本番環境で定期実行を設定
  config.after_initialize do
    # Solid Queue Recurring Jobsが利用可能な場合に設定
    if defined?(SolidQueue::RecurringJob)
      begin
        # テーブルが存在するかチェック
        if ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_jobs')
          # 既存のジョブがあるかチェック
          existing_job = SolidQueue::RecurringJob.where(key: 'poll_expiration').first
          
          unless existing_job
            SolidQueue::RecurringJob.create!(
              key: 'poll_expiration',
              class_name: 'PollExpirationJob',
              cron: '*/10 * * * *',  # 10分ごと
              priority: 5
            )
            Rails.logger.info "🗳️  Poll expiration job scheduled to run every 10 minutes"
          end
        end
      rescue => e
        Rails.logger.warn "Failed to create recurring poll expiration job: #{e.message}"
      end
    end
  end
end