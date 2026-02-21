# frozen_string_literal: true

module ActorAttachmentProcessing
  extend ActiveSupport::Concern

  private

  # ActivityPubデータからdisplay_nameをデコードして取得
  def decode_actor_display_name(actor_data)
    name = actor_data['name']
    return name if name.blank?

    CGI.unescapeHTML(name)
  end

  # ActivityPubデータからnote(summary)をデコードして取得
  # noteはHTMLを含むため、HTML構造を壊さないデコードを行う
  def decode_actor_note(actor_data)
    summary = actor_data['summary']
    return summary if summary.blank?

    decode_html_entities(summary)
  end

  def extract_fields_from_attachments(actor_data)
    attachments = actor_data['attachment'] || []
    return [] unless attachments.is_a?(Array)

    attachments.filter_map do |attachment|
      next unless attachment.is_a?(Hash) && attachment['type'] == 'PropertyValue'

      {
        name: decode_field_text(attachment['name']),
        value: decode_field_text(attachment['value'])
      }
    end
  end

  # フィールドのテキストをデコード（HTMLを含む可能性あり）
  def decode_field_text(text)
    return text if text.blank?

    if text.include?('<')
      decode_html_entities(text)
    else
      CGI.unescapeHTML(text)
    end
  end

  # ActivityPubのfeaturedフィールドからURLを抽出
  # bsky.brid.gy等はオブジェクトをインラインで返すため、Hashの場合はidを取得
  def extract_featured_url(featured)
    case featured
    when String then featured
    when Hash then featured['id']
    end
  end

  # HTMLコンテンツ内のエンティティをデコード（構造文字 <, >, & は保持）
  def decode_html_entities(text)
    return text if text.blank?

    result = text.gsub(/&#(\d+);/) do
      code = ::Regexp.last_match(1).to_i
      next ::Regexp.last_match(0) if [38, 60, 62].include?(code)

      [code].pack('U')
    rescue RangeError
      ::Regexp.last_match(0)
    end

    result = result.gsub(/&#x([0-9a-fA-F]+);/i) do
      code = ::Regexp.last_match(1).to_i(16)
      next ::Regexp.last_match(0) if [0x26, 0x3C, 0x3E].include?(code)

      [code].pack('U')
    rescue RangeError
      ::Regexp.last_match(0)
    end

    result.gsub('&apos;', "'")
          .gsub('&nbsp;', ' ')
          .gsub('&quot;', '"')
  end
end
