# frozen_string_literal: true

# 表示されたリモートカスタム絵文字の画像をR2にローカルキャッシュするジョブ。
# 直リンクを廃し、リモートCDNのホットリンク保護(Referer拒否)で画像が壊れる問題を回避する。
# CustomEmoji#url から死活バックオフ付き(12h)で投入される。
class CacheRemoteEmojiJob < ApplicationJob
  queue_as :default

  # 画像が消えた(=相手サーバで絵文字が差し替えられた)とみなすHTTPステータス
  GONE_PATTERN = /HTTP (404|410)\b/
  MAX_OWNER_REFRESH = 3

  def perform(emoji_id)
    emoji = CustomEmoji.find_by(id: emoji_id)
    return unless emoji&.remote?
    return if emoji.image.attached?

    result = RemoteEmojiCopyService.new.cache_in_place(emoji)
    refresh_profile_owners(emoji) if image_gone?(result)
  end

  private

  def image_gone?(result)
    result.is_a?(Hash) && !result[:success] && result[:error].to_s.match?(GONE_PATTERN)
  end

  # Mastodonは管理者が絵文字を差し替えてもUpdate(Person)を送らないため、プロフィール上の
  # 絵文字は古い画像URLのまま残る。その絵文字をプロフィールに含むアクターを再取得し、
  # 最新のtag(新しい画像URL)を取り込ませる(アバター再取得と同じ12hクールダウンを共有)
  def refresh_profile_owners(emoji)
    pattern = "%:#{ActiveRecord::Base.sanitize_sql_like(emoji.shortcode)}:%"
    owners = Actor.where(local: false, domain: emoji.domain)
                  .where("display_name LIKE :p ESCAPE '\\' OR note LIKE :p ESCAPE '\\' OR fields LIKE :p ESCAPE '\\'",
                         p: pattern)
                  .limit(MAX_OWNER_REFRESH)

    owners.each do |actor|
      next unless Rails.cache.write("avatar_refresh:#{actor.id}", true, expires_in: 12.hours, unless_exist: true)

      RefreshRemoteActorJob.perform_later(actor.id)
    end
  end
end
