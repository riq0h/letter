# frozen_string_literal: true

# 表示されたリモートカスタム絵文字の画像をR2にローカルキャッシュするジョブ。
# 直リンクを廃し、リモートCDNのホットリンク保護(Referer拒否)で画像が壊れる問題を回避する。
# CustomEmoji#url から死活バックオフ付き(12h)で投入される。
class CacheRemoteEmojiJob < ApplicationJob
  queue_as :default

  def perform(emoji_id)
    emoji = CustomEmoji.find_by(id: emoji_id)
    return unless emoji&.remote?
    return if emoji.image.attached?

    RemoteEmojiCopyService.new.cache_in_place(emoji)
  end
end
