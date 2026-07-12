# frozen_string_literal: true

# 受信した絵文字リアクション(投稿詳細ページの掲示専用)のヘルパ
module ReactionsHelper
  # ":name:" 形式のリアクションに対応するカスタム絵文字レコードを解決する。
  # リアクションしたアクターのドメインを優先し、無ければ全ドメインから探す。
  # Unicode絵文字や未解決の場合はnil(呼び出し側でテキスト表示にフォールバック)。
  def reaction_custom_emoji(reaction, favourites)
    shortcode = reaction[/\A:([a-z0-9_-]+):\z/, 1]
    return nil unless shortcode

    domains = favourites.filter_map { |f| f.actor&.domain }.uniq
    emoji = CustomEmoji.enabled.remote.where(shortcode: shortcode, domain: domains).first ||
            CustomEmoji.enabled.remote.find_by(shortcode: shortcode)
    # 表示契機: 未キャッシュ(古い既存レコード等)ならR2取り込みを予約する。
    # 他の表示経路(to_activitypub/EmojiPresenter/EmojiFormatter)と同じ扱い
    emoji&.request_remote_image_cache
    emoji
  end

  # テキスト表示のフォールバック。旧Misskeyの名前付きリアクション(star等)が
  # 生のまま保存されている過去データもUnicode絵文字にして表示する
  def reaction_display_text(reaction)
    Favourite::LEGACY_MISSKEY_REACTIONS[reaction] || reaction
  end

  # ホバー時に「誰がリアクションしたか」を示すtitle文字列
  def reaction_title(reaction, favourites)
    names = favourites.first(10).map { |f| "@#{f.actor.full_username}" }
    names << "他#{favourites.size - 10}人" if favourites.size > 10
    "#{reaction} — #{names.join('、')}"
  end
end
