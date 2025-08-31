# frozen_string_literal: true

module ActivityPubMediaHandler
  extend ActiveSupport::Concern

  private

  def handle_media_attachments(object, object_data)
    attachments = object_data['attachment']
    return unless attachments.is_a?(Array) && attachments.any?

    attachments.each do |attachment|
      next unless attachment.is_a?(Hash)

      # Mastodon標準の'Document'と、bsky.brid.gyの'Image'/'Video'をサポート
      attachment_type = attachment['type']
      next unless %w[Document Image Video].include?(attachment_type)

      create_media_attachment(object, attachment)
    end
  end

  def create_media_attachment(object, attachment_data)
    url = attachment_data['url']
    file_name = extract_filename_from_url(url)

    # mediaTypeが空またはnilの場合、typeフィールドから推測
    media_type = determine_media_type_from_attachment(attachment_data)

    media_attrs = build_media_attachment_attributes(object, attachment_data, url, media_type, file_name)
    MediaAttachment.create!(media_attrs)
    Rails.logger.info "📎 Media attachment created for object #{object.id}: #{url}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "⚠️ Failed to create media attachment: #{e.message}"
  end

  def build_media_attachment_attributes(object, attachment_data, url, media_type, file_name)
    # content_typeが空の場合、media_typeから推測
    content_type = attachment_data['mediaType']
    if content_type.blank? || content_type == ''
      content_type = case media_type
                     when 'video'
                       'video/mp4'
                     else
                       'image/jpeg' # image または不明な場合のデフォルト
                     end
    end

    {
      actor: object.actor,
      object: object,
      remote_url: url,
      content_type: content_type,
      media_type: media_type,
      file_name: file_name,
      file_size: 1,
      description: attachment_data['name'],
      width: attachment_data['width'],
      height: attachment_data['height'],
      blurhash: attachment_data['blurhash']
    }
  end

  def extract_filename_from_url(url)
    UrlFilename.from_url(url).to_s
  end

  def determine_media_type_from_content_type(content_type)
    MediaTypeDetector.determine(content_type)
  end

  def determine_media_type_from_attachment(attachment_data)
    content_type = attachment_data['mediaType']

    # mediaTypeが有効な場合はそれを使用
    return determine_media_type_from_content_type(content_type) if content_type.present? && content_type != ''

    # mediaTypeが空の場合、typeフィールドから推測
    attachment_type = attachment_data['type']
    case attachment_type
    when 'Video'
      'video'
    when 'Document'
      # URLから拡張子を推測
      url = attachment_data['url']
      return 'video' if url&.match?(/\.(mp4|mov|webm|avi)$/i)

      'image' # 画像拡張子または不明な場合
    else
      'image' # Image または不明な場合は画像とする
    end
  end
end
