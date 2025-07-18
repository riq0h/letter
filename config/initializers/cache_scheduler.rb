# frozen_string_literal: true

# キャッシュクリーンアップの定期実行設定
Rails.application.configure do
  # 本番環境またはSolid Queueが有効な場合のみ定期実行を設定
  if Rails.env.production? || ENV['ENABLE_CACHE_CLEANUP'] == 'true'
    # 毎日深夜2時にキャッシュクリーンアップを実行
    config.after_initialize do
      # Solid Queue Recurring Jobsが利用可能な場合に設定
      if defined?(SolidQueue::RecurringJob)
        begin
          # テーブルが存在するかチェック
          if ActiveRecord::Base.connection.table_exists?('solid_queue_recurring_jobs')
            # 既存のジョブがあるかチェック
            existing_job = SolidQueue::RecurringJob.where(key: 'cache_cleanup').first
            
            unless existing_job
              SolidQueue::RecurringJob.create!(
                key: 'cache_cleanup',
                class_name: 'CacheCleanupJob',
                cron: '0 2 * * *',  # 毎日2:00 AM
                priority: 10
              )
            end
          end
        rescue => e
          Rails.logger.warn "Failed to create recurring cache cleanup job: #{e.message}"
        end
      end
    end
  end
end