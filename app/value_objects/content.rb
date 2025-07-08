# frozen_string_literal: true

# テキストコンテンツを表すValueObject
# ハッシュタグ、メンション、カスタム絵文字の抽出機能を提供
class Content
  HASHTAG_REGEX = /#([a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]+)/
  MENTION_REGEX = /@([a-zA-Z0-9_.-]+)(?:@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}))?/

  attr_reader :text, :hashtags, :mentions, :custom_emojis

  def initialize(text)
    @text = text.to_s.strip
    @hashtags = extract_hashtags
    @mentions = extract_mentions
    @custom_emojis = extract_custom_emojis
    freeze
  end

  # ファクトリメソッド
  def self.parse(text)
    new(text)
  end

  # 空のコンテンツかどうか
  def empty?
    text.blank?
  end

  # コンテンツの長さ
  delegate :length, to: :text

  # ハッシュタグが含まれているか
  def hashtags?
    hashtags.any?
  end

  # メンションが含まれているか
  def mentions?
    mentions.any?
  end

  # カスタム絵文字が含まれているか
  def custom_emojis?
    custom_emojis.any?
  end

  # オブジェクトに対して関連データを作成
  def process_for_object(object)
    create_hashtags_for_object(object)
    create_mentions_for_object(object)
  end

  # 文字列表現
  def to_s
    text
  end

  # 等価性の判定
  def ==(other)
    return false unless other.is_a?(Content)

    text == other.text
  end

  alias eql? ==

  delegate :hash, to: :text

  private

  def extract_hashtags
    text.scan(HASHTAG_REGEX).flatten.map(&:downcase).uniq
  end

  def extract_mentions
    mention_data = text.scan(MENTION_REGEX).map do |username, domain|
      {
        username: username,
        domain: domain,
        acct: domain ? "#{username}@#{domain}" : username
      }
    end
    mention_data.uniq { |m| m[:acct] }
  end

  def extract_custom_emojis
    CustomEmoji.from_text(text)
  end

  def create_hashtags_for_object(object)
    hashtags.each do |hashtag_name|
      tag = Tag.find_or_create_by(name: hashtag_name)
      object.object_tags.find_or_create_by(tag: tag)
    end
  end

  def create_mentions_for_object(object)
    mentions.each do |mention_data|
      actor = find_actor_by_mention(mention_data)
      next unless actor

      object.mentions.find_or_create_by(actor: actor)
    end
  end

  def find_actor_by_mention(mention_data)
    if mention_data[:domain]
      Actor.find_by(username: mention_data[:username], domain: mention_data[:domain])
    else
      Actor.find_by(username: mention_data[:username], local: true)
    end
  end
end
