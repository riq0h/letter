# frozen_string_literal: true

module ActivityPubVisibilityHelper
  extend ActiveSupport::Concern

  private

  def determine_visibility(object_data)
    to = Array(object_data['to'])
    cc = Array(object_data['cc'])

    public_collection = 'https://www.w3.org/ns/activitystreams#Public'

    # Public: as:Public が to に含まれる
    return 'public' if to.include?(public_collection)

    # Unlisted: as:Public が cc に含まれる
    return 'unlisted' if cc.include?(public_collection)

    # Private: 宛先にフォロワーコレクションを含む(フォロワー限定。メンション付きのリプライもここ)。
    # 以前はフォロワーコレクションを含んでいてもDM扱いしており、フォロワー限定のリプライが
    # DMとしてホームTLから除外されていた
    return 'private' if (to + cc).any? { |recipient| followers_collection?(recipient) }

    # Direct: メンションされたアクターのみが宛先
    mentions = extract_mentions_from_tags(object_data['tag'])
    return 'direct' if mentions.any? && (to + cc).all? { |recipient| mentions.include?(recipient) }

    # Private: フォロワーのみ（as:Public が含まれない）
    'private'
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
