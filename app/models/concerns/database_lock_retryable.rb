# frozen_string_literal: true

# SQLiteの一過性ロック競合（SQLite3::BusyException: "database is locked"）を
# その場でリトライするための共通ヘルパー。
#
# database.ymlは default_transaction_mode: :deferred を使っており、読み取りロック
# 取得後に書き込みへ昇格する際、他接続が書き込みロックを持つと busy_timeout を
# 待たず即SQLITE_BUSYを返す（待つとデッドロックの危険があるため）。
# このため連合受信のような同時書き込みが起きる経路では稀にBusyExceptionが発生し、
# 握り潰すと連合コンテンツ（投稿・リブログ）の取りこぼしになる。
#
# トランザクションモードを :immediate にする手もあるが、その場合は競合時に
# busy_timeout(60秒)まで待つためpumaの60秒ワーカータイムアウトを誘発しうる。
# そこで全体の挙動は変えず、書き込み箇所をこのヘルパーで包んで短時間リトライする
# （既存の statuses/timelines/push コントローラと同じ方式）。
module DatabaseLockRetryable
  MAX_LOCK_RETRIES = 3

  private

  def with_database_lock_retry(max_retries: MAX_LOCK_RETRIES)
    retries = 0
    begin
      yield
    rescue ActiveRecord::StatementInvalid => e
      raise unless e.message.include?('database is locked') && retries < max_retries

      retries += 1
      sleep(0.1 * retries)
      retry
    end
  end
end
