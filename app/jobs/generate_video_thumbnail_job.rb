# frozen_string_literal: true

class GenerateVideoThumbnailJob < ApplicationJob
  include BlobStorage
  include SsrfProtection

  queue_as :default

  def perform(media_attachment_id)
    media_attachment = MediaAttachment.find_by(id: media_attachment_id)
    return unless media_attachment
    return if media_attachment.thumbnail.attached?
    return unless media_attachment.video?

    thumbnail_io = generate_thumbnail(media_attachment)
    return unless thumbnail_io

    blob = create_storage_blob(
      io: thumbnail_io,
      filename: "thumb_#{media_attachment_id}.jpg",
      content_type: 'image/jpeg',
      folder: 'thumb'
    )
    media_attachment.thumbnail.attach(blob)
  rescue StandardError => e
    Rails.logger.error "Failed to generate video thumbnail for #{media_attachment_id}: #{e.message}"
  end

  private

  def generate_thumbnail(media_attachment)
    if media_attachment.file.attached?
      extract_frame_from_local_video(media_attachment)
    elsif media_attachment.remote_url.present?
      if media_attachment.remote_url.include?('bsky.network/xrpc/')
        fetch_bluesky_thumbnail(media_attachment.remote_url)
      else
        extract_frame_from_remote_video(media_attachment.remote_url)
      end
    end
  end

  def extract_frame_from_local_video(media_attachment)
    input_file = Tempfile.new(['input_video', File.extname(media_attachment.file_name)])
    input_file.binmode
    input_file.write(media_attachment.file.download)
    input_file.close

    extract_frame_with_ffmpeg(input_file.path)
  ensure
    input_file&.unlink
  end

  def extract_frame_from_remote_video(url)
    return nil unless validate_url_for_ssrf!(url)

    extract_frame_with_ffmpeg(url)
  end

  def extract_frame_with_ffmpeg(input_path)
    output_file = Tempfile.new(['thumbnail', '.jpg'])
    output_file.close

    cmd = [
      'ffmpeg',
      '-ss', '1',
      '-i', input_path,
      '-vframes', '1',
      '-q:v', '2',
      '-y',
      output_file.path
    ]

    _, stderr, status = Open3.capture3(*cmd)

    if status.success? && File.exist?(output_file.path) && File.size(output_file.path).positive?
      StringIO.new(File.binread(output_file.path))
    else
      Rails.logger.error "FFmpeg thumbnail extraction failed: #{stderr}"
      nil
    end
  ensure
    output_file&.unlink
  end

  def fetch_bluesky_thumbnail(url)
    uri = URI.parse(url)
    params = URI.decode_www_form(uri.query || '').to_h
    did = params['did']
    cid = params['cid']
    return nil unless did.present? && cid.present?

    thumbnail_url = "https://video.bsky.app/watch/#{CGI.escape(did)}/#{cid}/thumbnail.jpg"
    response = HTTParty.get(thumbnail_url, timeout: 10, follow_redirects: true)

    return nil unless response.success? && response.body.present?

    StringIO.new(response.body)
  rescue StandardError => e
    Rails.logger.warn "Failed to fetch Bluesky video thumbnail: #{e.message}"
    nil
  end
end
