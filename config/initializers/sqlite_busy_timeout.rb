# frozen_string_literal: true

# SQLiteのbusy_handlerを設定
# 標準のbusy_timeoutはGVLを保持したまま待機するため、
# 他のRubyスレッドがブロックされてスループットが低下する。
# カスタムbusy_handlerはRuby側でsleepしGVLを解放することで
# 待機中も他のスレッドが実行可能になる。
ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::SQLite3Adapter.prepend(Module.new do
    def configure_connection
      super

      # 既存のbusy_timeoutを無効化
      raw_connection.busy_timeout(0)

      # カスタムbusy_handler: GVLを解放する1msスリープで再試行
      # 最大15秒（15000回）まで再試行
      raw_connection.busy_handler do |count|
        if count < 15_000
          sleep(0.001) # 1ms - GVLが解放される
          true # 再試行する
        else
          false # タイムアウト
        end
      end
    end
  end)
end
