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

    # Direct: 特定のアクターのみが対象で、mentions がある
    mentions = extract_mentions_from_tags(object_data['tag'])
    return 'direct' if mentions.any? && (to + cc).all? { |recipient| mentions.include?(recipient) || recipient.include?('/followers') }

    # Private: フォロワーのみ（as:Public が含まれない）
    'private'
  end

  def extract_mentions_from_tags(tags)
    return [] unless tags.is_a?(Array)

    tags.select { |tag| tag['type'] == 'Mention' }
        .pluck('href')
        .compact
  end
end
