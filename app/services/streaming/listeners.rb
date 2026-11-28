# frozen_string_literal: true

module Streaming
  # いまストリーミングを受け取っている接続があるかの目印。接続を持つプロセス(Hub)が定期的に付け直し、
  # 出来事を記録する側はこれを見て、誰も受け取らない出来事を記録しない。
  # プロセスをまたいで見えるよう、キャッシュ(Solid Cache)に置く
  module Listeners
    # Hubが付け直す間隔(Hub::MARK_INTERVAL)より十分長くする
    TTL = 1.minute

    ANY_KEY = 'streaming:listening'
    TIMELINES_KEY = 'streaming:listening:timelines'

    module_function

    # user_idを渡すとその人の接続があるか、渡さなければ誰かの接続があるか
    def listening?(user_id = nil)
      Rails.cache.exist?(user_id ? user_key(user_id) : ANY_KEY)
    rescue StandardError
      false
    end

    # 公開・ハッシュタグ・リストのタイムラインを購読している接続があるか
    def timelines_listening?
      Rails.cache.exist?(TIMELINES_KEY)
    rescue StandardError
      false
    end

    def mark(user_ids:, timelines:)
      return if user_ids.empty?

      Rails.cache.write(ANY_KEY, true, expires_in: TTL)
      user_ids.each { |id| Rails.cache.write(user_key(id), true, expires_in: TTL) }
      Rails.cache.write(TIMELINES_KEY, true, expires_in: TTL) if timelines
    rescue StandardError => e
      Rails.logger.warn "📡 Failed to mark streaming listeners: #{e.message}"
    end

    def user_key(user_id)
      "streaming:listening:user:#{user_id}"
    end
  end
end
