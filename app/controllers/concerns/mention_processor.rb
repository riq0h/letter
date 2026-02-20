# frozen_string_literal: true

module MentionProcessor
  extend ActiveSupport::Concern

  private

  def process_mentions_and_tags
    return if @status.content.blank?

    process_mentions
    process_hashtags
  end

  def process_mentions
    return if @mentions.blank?

    if @mentions.is_a?(Array)
      process_explicit_mentions(@mentions)
    else
      extract_and_process_mentions
    end
  end

  def process_explicit_mentions(mentions_param)
    mentions_param.each do |username|
      mentioned_actor = Actor.find_by(username: username.delete('@'))
      create_mention_for(mentioned_actor) if mentioned_actor && mentioned_actor != current_user
    end
  end

  def extract_and_process_mentions
    mentioned_usernames = extract_mentioned_usernames(@status.content)
    mentioned_usernames.each do |username|
      mentioned_actor = Actor.find_by(username: username)
      create_mention_for(mentioned_actor) if mentioned_actor && mentioned_actor != current_user
    end
  end

  def extract_mentioned_usernames(content)
    content.scan(/@([a-zA-Z0-9_.-]+)/).flatten.uniq
  end

  def create_mention_for(actor)
    Mention.find_or_create_by(object: @status, actor: actor)
  end

  def process_hashtags
    tag_names = extract_hashtag_names(@status.content)
    tag_names.each do |tag_name|
      tag = Tag.find_or_create_by_display_name(tag_name)
      ObjectTag.find_or_create_by(object: @status, tag: tag)
    end
  end

  def extract_hashtag_names(content)
    content.scan(/#([\w\u0080-\uFFFF]+)/).flatten.uniq
  end
end
