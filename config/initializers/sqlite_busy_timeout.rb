# frozen_string_literal: true

# SQLiteの接続レベル設定
# database.ymlのpragmaでは反映されない設定を明示的に適用する
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(Module.new do
    def configure_connection
      super

      raw_connection.busy_timeout(15_000)
      raw_connection.execute('PRAGMA mmap_size=2147483648') # 2GB
    end
  end)
end
