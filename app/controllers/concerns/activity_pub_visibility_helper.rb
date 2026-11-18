# frozen_string_literal: true

module ActivityPubVisibilityHelper
  extend ActiveSupport::Concern

  # 公開コレクションの表記。JSON-LDの短縮形(as:Public / Public)も仕様上同じ意味で、
  # Fedify製のサーバ(Hollo等)は as:Public で送ってくる。Mastodonも3つとも公開として扱う
  PUBLIC_COLLECTION_URIS = %w[https://www.w3.org/ns/activitystreams#Public as:Public Public].freeze

  private

  def determine_visibility(object_data)
    to = Array(object_data['to'])
    cc = Array(object_data['cc'])

    # Public: 公開コレクションが to に含まれる
    return 'public' if to.any? { |recipient| public_collection?(recipient) }

    # Unlisted: 公開コレクションが cc に含まれる
    return 'unlisted' if cc.any? { |recipient| public_collection?(recipient) }

    # Private: 宛先にフォロワーコレクションを含む(フォロワー限定。メンション付きのリプライもここ)
    return 'private' if (to + cc).any? { |recipient| followers_collection?(recipient) }

    # Direct: メンションされたアクターのみが宛先
    mentions = extract_mentions_from_tags(object_data['tag'])
    return 'direct' if mentions.any? && (to + cc).all? { |recipient| mentions.include?(recipient) }

    # Private: フォロワーのみ（as:Public が含まれない）
    'private'
  end

  def public_collection?(recipient)
    PUBLIC_COLLECTION_URIS.include?(recipient)
  end

  # Mastodon/Misskey/Pleroma/GoToSocial のフォロワーコレクションは actor URL + /followers
  def followers_collection?(recipient)
    recipient.is_a?(String) && recipient.end_with?('/followers')
  end

  def extract_mentions_from_tags(tags)
    # tagは単一オブジェクトのこともある。is_a?(Array)前提だと単一Mentionを取りこぼし
    # DM等の可視性を誤判定するため、Array.wrapで正規化する
    Array.wrap(tags)
         .select { |tag| tag.is_a?(Hash) && tag['type'] == 'Mention' }
         .pluck('href')
         .compact
  end
end
