# frozen_string_literal: true

module MentionTagSerializer
  extend ActiveSupport::Concern

  private

  def serialized_mentions(status)
    # 防御的プログラミング: 常に配列を返し、nullは返さない
    return [] unless status.respond_to?(:mentions)
    return [] if status.mentions.nil?

    mentions = status.mentions.includes(:actor).filter_map do |mention|
      serialize_mention(mention)
    end

    # 常に配列であることを保証
    mentions.is_a?(Array) ? mentions : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize mentions for status #{status.id}: #{e.message}"
    Rails.logger.warn "Backtrace: #{e.backtrace.first(3).join(', ')}"
    [] # エラー時は常に空配列を返す
  end

  def serialize_mention(mention)
    # メンションとアクターの存在をバリデート
    return nil unless mention&.actor

    {
      id: mention.actor.id.to_s,
      username: mention.actor.username.to_s,
      acct: mention.acct.to_s,
      url: mention_url(mention.actor)
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize mention #{mention&.id}: #{e.message}"
    nil
  end

  def mention_url(actor)
    return '' unless actor

    if actor.local?
      "#{Rails.application.config.activitypub.scheme}://#{Rails.application.config.activitypub.domain}/users/#{actor.username}"
    else
      actor.ap_id.to_s
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to build mention URL for actor #{actor&.id}: #{e.message}"
    '' # エラー時は空文字列を返す
  end

  def serialized_tags(status)
    # 防御的プログラミング: 常に配列を返し、nullは返さない
    return [] unless status.respond_to?(:tags)
    return [] if status.tags.nil?

    tags = status.tags.filter_map do |tag|
      serialize_tag(tag)
    end

    # 常に配列であることを保証
    tags.is_a?(Array) ? tags : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize tags for status #{status.id}: #{e.message}"
    Rails.logger.warn "Backtrace: #{e.backtrace.first(3).join(', ')}"
    [] # エラー時は常に空配列を返す
  end

  def serialize_tag(tag)
    # タグ名の存在をバリデート
    return nil unless tag&.name

    {
      name: tag.name.to_s,
      url: "#{Rails.application.config.activitypub.scheme}://#{Rails.application.config.activitypub.domain}/tags/#{tag.name}"
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize tag #{tag&.id}: #{e.message}"
    nil
  end
end
