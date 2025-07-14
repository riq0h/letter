# frozen_string_literal: true

module Letter
  # Mastodon互換のSnowflake ID生成
  # 48ビットタイムスタンプ + 16ビットシーケンス = 64ビット整数（文字列として処理）
  class Snowflake
    # エポック（2016年3月16日 00:00:00 UTC）
    EPOCH = Time.new(2016, 3, 16, 0, 0, 0, '+00:00').to_i * 1000

    # ビット配置
    TIMESTAMP_BITS = 48
    SEQUENCE_BITS = 16

    # マスク
    SEQUENCE_MASK = (1 << SEQUENCE_BITS) - 1

    class << self
      # Snowflake IDを生成
      def generate
        timestamp_ms = current_timestamp
        sequence = generate_sequence

        # 48ビットタイムスタンプ + 16ビットシーケンス
        id = (timestamp_ms << SEQUENCE_BITS) | sequence
        id.to_s
      end

      # 指定した時刻のSnowflake IDを生成（テスト用）
      def generate_at(timestamp, sequence: nil)
        timestamp_ms = timestamp_to_ms(timestamp)
        sequence ||= generate_sequence

        id = (timestamp_ms << SEQUENCE_BITS) | sequence
        id.to_s
      end

      # Snowflake IDから時刻を抽出
      def extract_timestamp(snowflake_id)
        id = snowflake_id.to_i
        timestamp_ms = id >> SEQUENCE_BITS
        timestamp_ms += EPOCH
        Time.at(timestamp_ms / 1000.0).utc
      end

      # Snowflake IDからシーケンス番号を抽出
      def extract_sequence(snowflake_id)
        id = snowflake_id.to_i
        id & SEQUENCE_MASK
      end

      # 時刻をミリ秒タイムスタンプに変換
      def timestamp_to_ms(timestamp)
        case timestamp
        when Time
          ((timestamp.to_f * 1000).to_i - EPOCH).abs
        when Integer
          ((timestamp * 1000) - EPOCH).abs
        else
          raise ArgumentError, "Invalid timestamp type: #{timestamp.class}"
        end
      end

      private

      # 現在時刻のミリ秒タイムスタンプを取得
      def current_timestamp
        ((Time.current.to_f * 1000).to_i - EPOCH).abs
      end

      # シーケンス番号を生成（16ビット）
      def generate_sequence
        SecureRandom.random_number(2**SEQUENCE_BITS)
      end
    end
  end
end
