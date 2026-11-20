# frozen_string_literal: true

class GenerateVideoThumbnailJob < ApplicationJob
  include BlobStorage
  include SsrfProtection

  queue_as :default

  # 他サーバの動画は、登録時とダウンロード後の2回このジョブが登録される。
  # 同じ動画では1つずつ動かし、後のジョブはサムネイルが付いているのを見て何もせず終わる
  limits_concurrency to: 1, key: ->(media_attachment_id) { media_attachment_id }, duration: 15.minutes

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
    media_attachment.fill_placeholder_blurhash { BlurhashGenerator.from_buffer(thumbnail_io.string) }
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

    if VideoFrameExtractor.extract(input_path, output_file.path)
      StringIO.new(File.binread(output_file.path))
    else
      Rails.logger.error "FFmpeg thumbnail extraction failed: #{input_path}"
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
