# frozen_string_literal: true

# SQLiteのANALYZEを定期的に実行し、クエリプランナーの統計情報を最新に保つ
# 統計情報がないとSQLiteは不適切なインデックスを選択する可能性がある
ActiveSupport.on_load(:active_record) do
  Rails.application.config.after_initialize do
    next unless ActiveRecord::Base.connection.adapter_name == 'SQLite'

    Thread.new do
      sleep 30 # SolidQueueなどの起動処理が完全に落ち着いてから実行

      retries = 0
      begin
        ActiveRecord::Base.connection_pool.with_connection do |conn|
          # スキャン行数を制限して高速に完了させ、ロック保持時間を短縮
          conn.execute('PRAGMA analysis_limit=1000')
          conn.execute('ANALYZE')
          Rails.logger.info '[SQLite] ANALYZE completed successfully'
        end
      rescue ActiveRecord::StatementInvalid => e
        retries += 1
        if retries <= 3 && e.message.include?('database is locked')
          sleep 30
          retry
        end
        Rails.logger.warn "[SQLite] ANALYZE failed: #{e.message}"
      end
    end
  end
end
