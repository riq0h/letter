# frozen_string_literal: true

require 'active_support'
require 'active_support/logger'
require 'active_support/tagged_logging'
require 'active_support/broadcast_logger'

# 標準出力とファイルの両方に書くロガー。ファイル側はタグ付きロガーとフォーマッタを共有して、
# リクエストIDなどのタグもそのまま残す。
# タグ付きのロガーを1つに限っているのは、BroadcastLoggerが自前で持たないメソッド(taggedなど)を
# 応答できる全ロガーに転送するため。タグ付きが2つあると、taggedに渡したブロック(ジョブの実行など)が2回走る
module PersistentLogger
  def self.build(stdout, path, generations:, size:)
    tagged = ActiveSupport::TaggedLogging.logger(stdout)
    file = ActiveSupport::Logger.new(path, generations, size)
    file.formatter = tagged.formatter
    ActiveSupport::BroadcastLogger.new(tagged, file)
  end
end
