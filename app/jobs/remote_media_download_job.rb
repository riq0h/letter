# frozen_string_literal: true

# リモートメディアをダウンロードしてActive Storageにキャッシュするジョブ
class RemoteMediaDownloadJob < ApplicationJob
  include BlobStorage
  include SsrfProtection

  queue_as :default

  MAX_VIDEO_SIZE = 300.megabytes
  MAX_IMAGE_SIZE = 30.megabytes
  DOWNLOAD_TIMEOUT = 60
  MAX_REDIRECTS = 5

  def perform(media_attachment_id)
    media = MediaAttachment.find_by(id: media_attachment_id)
    return if media.nil? || media.file.attached?
    return if media.remote_url.blank?
    return unless validate_url_for_ssrf!(media.remote_url)

    download_and_attach(media)
  rescue StandardError => e
    Rails.logger.warn "RemoteMediaDownloadJob failed for #{media_attachment_id}: #{e.message}"
  end

  private

  def download_and_attach(media)
    max_size = media.video? ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE

    tempfile = download_to_tempfile(media.remote_url, max_size)
    return unless tempfile

    begin
      content_type = detect_content_type(tempfile, media)

      blob = create_storage_blob(
        io: File.open(tempfile.path, 'rb'),
        filename: media.file_name.presence || "media_#{media.id}",
        content_type: content_type,
        folder: 'cache'
      )

      media.file.attach(blob)
      media.update_columns(
        processing_status: 'cached',
        file_size: blob.byte_size,
        content_type: content_type
      )

      GenerateVideoThumbnailJob.perform_later(media.id) if media.video? && !media.thumbnail.attached?

      Rails.logger.info "📦 Remote media cached: #{media.id} (#{blob.byte_size} bytes)"
    ensure
      tempfile.close!
    end
  end

  def download_to_tempfile(url, max_size)
    uri = URI.parse(url)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    tempfile = Tempfile.new(['remote_media', '.bin'], binmode: true)

    # リダイレクトを追従してダウンロード
    final_uri = follow_redirects(uri)
    return nil unless final_uri

    stream_response(final_uri, tempfile, max_size)

    tempfile.rewind
    tempfile
  rescue StandardError => e
    tempfile&.close!
    Rails.logger.warn "RemoteMediaDownloadJob: download failed: #{e.message}"
    nil
  end

  def follow_redirects(uri, limit = MAX_REDIRECTS)
    raise 'too many redirects' if limit <= 0

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                        open_timeout: 10, read_timeout: 10) do |http|
      response = http.head(uri)

      case response
      when Net::HTTPSuccess
        uri
      when Net::HTTPRedirection
        redirect_uri = URI.parse(response['location'])
        # 相対URLの場合は元のホストを使う
        redirect_uri = URI.join("#{uri.scheme}://#{uri.host}", response['location']) unless redirect_uri.host
        return nil unless validate_url_for_ssrf!(redirect_uri.to_s)

        follow_redirects(redirect_uri, limit - 1)
      else
        raise "HTTP #{response.code}"
      end
    end
  end

  def stream_response(uri, tempfile, max_size)
    downloaded_size = 0

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                        read_timeout: DOWNLOAD_TIMEOUT,
                                        open_timeout: 10) do |http|
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = InstanceConfig.user_agent

      http.request(request) do |response|
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          downloaded_size += chunk.bytesize
          raise "file too large (>#{max_size} bytes)" if downloaded_size > max_size

          tempfile.write(chunk)
        end
      end
    end
  end

  def detect_content_type(tempfile, media)
    detected = Marcel::MimeType.for(tempfile, name: media.file_name)
    detected.presence || media.content_type || 'application/octet-stream'
  end
end
