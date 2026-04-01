# frozen_string_literal: true

# SQLiteのbusy_timeoutを設定
# PRAGMAやdatabase.ymlのtimeoutでは反映されないため、
# コネクション確立時にRubyレベルで直接設定する
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(Module.new do
    def configure_connection
      super
      raw_connection.busy_timeout(15_000)
    end
  end)
end
