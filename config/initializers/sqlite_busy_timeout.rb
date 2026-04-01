# frozen_string_literal: true

# SQLiteのbusy_timeoutを設定
# database.ymlのtimeoutとは別に、接続レベルで明示的に設定する
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(Module.new do
    def configure_connection
      super

      raw_connection.busy_timeout(15_000) # 15秒
    end
  end)
end
