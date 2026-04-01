# frozen_string_literal: true

# SQLiteのANALYZEを定期的に実行し、クエリプランナーの統計情報を最新に保つ
# 統計情報がないとSQLiteは不適切なインデックスを選択する可能性がある
ActiveSupport.on_load(:active_record) do
  Rails.application.config.after_initialize do
    next unless ActiveRecord::Base.connection.adapter_name == 'SQLite'

    # 起動時にANALYZEを実行（バックグラウンドで）
    Thread.new do
      sleep 5 # 起動処理が落ち着いてから実行
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute('ANALYZE')
        Rails.logger.info '[SQLite] ANALYZE completed successfully'
      end
    rescue StandardError => e
      Rails.logger.warn "[SQLite] ANALYZE failed: #{e.message}"
    end
  end
end
