# frozen_string_literal: true

module EmojiTagProcessing
  extend ActiveSupport::Concern

  private

  # ActivityPubのtagデータからEmoji型タグを処理し、CustomEmojiレコードを作成する
  def process_emoji_tags(tags_data, domain:)
    tags = Array(tags_data)
    emoji_tags = tags.select { |tag| tag['type'] == 'Emoji' }

    emoji_tags.each do |emoji_tag|
      shortcode = emoji_tag['name']&.gsub(/^:|:$/, '')
      icon_url = emoji_tag.dig('icon', 'url')

      next unless shortcode.present? && icon_url.present?
      next if domain.blank?
      next if CustomEmoji.find_by(shortcode: shortcode, domain: domain)

      CustomEmoji.create!(
        shortcode: shortcode,
        domain: domain,
        image_url: icon_url,
        visible_in_picker: false,
        disabled: false
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to process emoji tags: #{e.message}"
  end
end
