# frozen_string_literal: true

module ActivityPubMediaHandler
  extend ActiveSupport::Concern

  private

  def handle_media_attachments(object, object_data)
    attachments = object_data['attachment']
    return unless attachments.is_a?(Array) && attachments.any?

    attachments.each do |attachment|
      next unless attachment.is_a?(Hash) && attachment['type'] == 'Document'

      create_media_attachment(object, attachment)
    end
  end

  def create_media_attachment(object, attachment_data)
    url = attachment_data['url']
    file_name = extract_filename_from_url(url)
    media_type = determine_media_type_from_content_type(attachment_data['mediaType'])

    media_attrs = build_media_attachment_attributes(object, attachment_data, url, media_type, file_name)
    MediaAttachment.create!(media_attrs)
    Rails.logger.info "📎 Media attachment created for object #{object.id}: #{url}"
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "⚠️ Failed to create media attachment: #{e.message}"
  end

  def build_media_attachment_attributes(object, attachment_data, url, media_type, file_name)
    {
      actor: object.actor,
      object: object,
      remote_url: url,
      content_type: attachment_data['mediaType'],
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
end
