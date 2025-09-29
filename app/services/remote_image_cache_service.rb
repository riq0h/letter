# frozen_string_literal: true

# リモート画像のキャッシュサービス
# Solid Cacheを使用してリモート画像を一定期間キャッシュし、/cacheに保存
class RemoteImageCacheService
  CACHE_DURATION = 7.days # キャッシュ期間
  MAX_FILE_SIZE = 10.megabytes # 最大ファイルサイズ
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/jpg
    image/png
    image/gif
    image/webp
    image/avif
  ].freeze

  def self.cache_remote_image(remote_url, media_attachment = nil)
    new(remote_url, media_attachment).cache_image
  end

  def self.get_cached_image_url(remote_url)
    new(remote_url).cached_url
  end

  def initialize(remote_url, media_attachment = nil)
    @remote_url = remote_url
    @media_attachment = media_attachment
    @cache_key = "remote_image:#{Digest::SHA256.hexdigest(remote_url)}"
  end

  def cache_image
    return cached_url if cached_locally?

    download_and_cache_image
  rescue StandardError => e
    Rails.logger.warn "Failed to cache remote image #{@remote_url}: #{e.message}"
    @remote_url # フォールバックとして元のURLを返す
  end

  def cached_url
    return @remote_url unless cached_locally?

    cached_data = Rails.cache.read(@cache_key)
    return @remote_url unless cached_data

    # Active StorageのURLを生成
    blob_key = cached_data[:blob_key]
    blob = ActiveStorage::Blob.find_by(key: blob_key)
    return @remote_url unless blob&.attached?

    if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
      "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{blob.key}"
    else
      Rails.application.routes.url_helpers.url_for(blob)
    end
  end

  private

  def cached_locally?
    Rails.cache.exist?(@cache_key)
  end

  def download_and_cache_image
    uri = URI.parse(@remote_url)
    return @remote_url unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    response = fetch_remote_image(uri)
    return @remote_url unless response

    validate_image_response(response)
    save_to_storage(response)
  end

  def fetch_remote_image(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 10, open_timeout: 5) do |http|
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = InstanceConfig.user_agent

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)
      return nil if response.body.bytesize > MAX_FILE_SIZE

      response
    end
  end

  def validate_image_response(response)
    content_type_header = response['content-type']
    return unless content_type_header

    content_type = content_type_header.split(';').first.strip

    raise "Unsupported content type: #{content_type}" unless ALLOWED_CONTENT_TYPES.include?(content_type)

    return unless response.body.bytesize > MAX_FILE_SIZE

    raise "File too large: #{response.body.bytesize} bytes"
  end

  def save_to_storage(response)
    content_type_header = response['content-type']
    return @remote_url unless content_type_header

    content_type = content_type_header.split(';').first.strip
    extension = content_type_to_extension(content_type)
    filename = "cached_#{Digest::SHA256.hexdigest(@remote_url)[0, 16]}.#{extension}"

    blob = create_blob(response, content_type, filename)
    attach_to_media_attachment(blob, content_type, filename)
    cache_metadata(blob, content_type)

    cached_url
  end

  def create_blob(response, content_type, filename)
    io = StringIO.new(response.body)

    if ENV['S3_ENABLED'] == 'true'
      custom_key = "cache/#{SecureRandom.hex(16)}"
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
    else
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type
      )
    end
  end

  def attach_to_media_attachment(blob, content_type, filename)
    return unless @media_attachment && !@media_attachment.file.attached?

    @media_attachment.file.attach(blob)
    @media_attachment.update!(
      file_size: blob.byte_size,
      content_type: content_type,
      file_name: filename
    )
  end

  def cache_metadata(blob, content_type)
    cache_data = {
      blob_key: blob.key,
      content_type: content_type,
      file_size: blob.byte_size,
      cached_at: Time.current
    }

    Rails.cache.write(@cache_key, cache_data, expires_in: CACHE_DURATION)
  end

  def content_type_to_extension(content_type)
    case content_type
    when 'image/jpeg', 'image/jpg'
      'jpg'
    when 'image/png'
      'png'
    when 'image/gif'
      'gif'
    when 'image/webp'
      'webp'
    when 'image/avif'
      'avif'
    else
      'bin'
    end
  end
end
