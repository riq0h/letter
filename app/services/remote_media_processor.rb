# frozen_string_literal: true

class RemoteMediaProcessor
  require 'net/http'
  require 'uri'

  def self.process_attachments(activity_pub_object, attachments_data)
    attachments_data.each do |attachment_data|
      next unless attachment_data['type'] == 'Document'

      process_single_attachment(activity_pub_object, attachment_data)
    end
  end

  def self.process_single_attachment(activity_pub_object, attachment_data)
    image_url = attachment_data['url']
    return unless image_url

    uri = URI(image_url)
    response = Net::HTTP.get_response(uri)

    return unless response.is_a?(Net::HTTPSuccess)

    create_media_attachment(activity_pub_object, attachment_data, response)
  rescue StandardError => e
    Rails.logger.error "Failed to process remote media: #{e.message}"
    nil
  end

  def self.create_media_attachment(activity_pub_object, attachment_data, response)
    filename = extract_filename_from_url(attachment_data['url'])

    media = create_media_record(activity_pub_object, attachment_data, response, filename)
    attach_file_to_media(media, response, filename, attachment_data['mediaType'])

    media
  end

  def self.create_media_record(activity_pub_object, attachment_data, response, filename)
    MediaAttachment.create!(
      actor: activity_pub_object.actor,
      object: activity_pub_object,
      file_name: filename,
      content_type: attachment_data['mediaType'],
      file_size: response.body.bytesize,
      media_type: determine_media_type(attachment_data['mediaType']),
      width: attachment_data['width'],
      height: attachment_data['height'],
      blurhash: attachment_data['blurhash'],
      remote_url: attachment_data['url']
    )
  end

  def self.attach_file_to_media(media, response, filename, content_type)
    media.file.attach(
      io: StringIO.new(response.body),
      filename: filename,
      content_type: content_type
    )
  end

  def self.extract_filename_from_url(url)
    UrlFilename.from_url(url).to_s
  end

  def self.determine_media_type(content_type)
    MediaTypeDetector.determine(content_type)
  end
end
