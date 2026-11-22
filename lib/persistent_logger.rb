# frozen_string_literal: true

require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'
require 'active_support/broadcast_logger'

# 標準出力とファイルの両方に書くロガー。ファイル側はタグ付きロガーのフォーマッタを通して、
# リクエストIDなどのタグもそのまま残す。標準出力はDockerが時刻を付けるが、ファイルには無いので時刻と重要度を足す。
# タグ付きのロガーを1つに限っているのは、BroadcastLoggerが自前で持たないメソッド(taggedなど)を
# 応答できる全ロガーに転送するため。タグ付きが2つあると、taggedに渡したブロック(ジョブの実行など)が2回走る
module PersistentLogger
  def self.build(stdout, path, generations:, size:)
    tagged = ActiveSupport::TaggedLogging.logger(stdout)
    file = ActiveSupport::Logger.new(path, generations, size)
    logger = ActiveSupport::BroadcastLogger.new(tagged, file)
    # ActiveJobなどはlogger.formatterから今のタグを読むので、まとめ役にもタグ付きのフォーマッタを持たせる。
    # この代入は全ロガーに配られるので、ファイル側のフォーマッタはその後で設定する
    logger.formatter = tagged.formatter
    file.formatter = proc do |severity, time, progname, message|
      "#{time.utc.iso8601(3)} #{severity} #{tagged.formatter.call(severity, time, progname, message)}"
    end
    logger
  end
end
