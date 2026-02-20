# frozen_string_literal: true

module EmojiTagProcessing
  extend ActiveSupport::Concern

  private

  # ActivityPubのtagデータからEmoji型タグを処理し、CustomEmojiレコードを作成する
  def process_emoji_tags(tags_data, domain:)
    tags = Array(tags_data)
    emoji_tags = tags.select { |tag| tag['type'] == 'Emoji' }

    emoji_tags.each do |emoji_tag|
      process_single_emoji_tag(emoji_tag, domain)
    end
  end

  def process_single_emoji_tag(emoji_tag, domain)
    shortcode = emoji_tag['name']&.gsub(/^:|:$/, '')
    icon_url = emoji_tag.dig('icon', 'url')

    return unless shortcode.present? && icon_url.present?
    return if domain.blank?

    existing = CustomEmoji.find_by(shortcode: shortcode, domain: domain)
    if existing
      # URLが変更されている場合は更新
      existing.update!(image_url: icon_url) if existing.image_url != icon_url
    else
      CustomEmoji.create!(
        shortcode: shortcode,
        domain: domain,
        image_url: icon_url,
        visible_in_picker: false,
        disabled: false
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to process emoji tag :#{shortcode}: from #{domain}: #{e.message}"
  end
end
