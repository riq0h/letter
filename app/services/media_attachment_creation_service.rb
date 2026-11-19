# frozen_string_literal: true

class MediaAttachmentCreationService
  include BlobStorage

  def initialize(user:, description: nil, processing_status: nil)
    @user = user
    @description = description
    @processing_status = processing_status
  end

  # 許可されるMIMEタイプ
  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif image/avif].freeze
  ALLOWED_VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime video/ogg].freeze
  ALLOWED_AUDIO_TYPES = %w[audio/mpeg audio/ogg audio/wav audio/flac audio/aac audio/mp4].freeze
  ALLOWED_MIME_TYPES = (ALLOWED_IMAGE_TYPES + ALLOWED_VIDEO_TYPES + ALLOWED_AUDIO_TYPES).freeze

  # ファイルサイズ制限（MediaAttachmentモデルの定数を参照）
  MAX_IMAGE_SIZE = MediaAttachment::MAX_IMAGE_SIZE
  MAX_VIDEO_SIZE = MediaAttachment::MAX_VIDEO_SIZE

  def create_from_file(file)
    validate_file!(file)
    file_info = extract_file_info(file)
    metadata = extract_file_metadata(file, file_info[:media_type])

    build_media_attachment_with_active_storage(file, file_info, metadata)
  end

  private

  attr_reader :user, :description, :processing_status

  def validate_file!(file)
    # マジックバイトによるMIMEタイプ検出
    detected_type = Marcel::MimeType.for(file)
    file.rewind

    # マジックバイトで検出できない場合はクライアント提供のcontent_typeにフォールバック
    effective_type = if detected_type == 'application/octet-stream'
                       file.content_type || detected_type
                     else
                       detected_type
                     end

    raise ArgumentError, "File type not allowed: #{effective_type}" unless ALLOWED_MIME_TYPES.include?(effective_type)

    # ファイルサイズ制限
    max_size = effective_type.start_with?('video/') ? MAX_VIDEO_SIZE : MAX_IMAGE_SIZE
    return unless file.size > max_size

    raise ArgumentError, "File too large: #{file.size} bytes (max: #{max_size} bytes)"
  end

  def extract_file_info(file)
    filename = File.basename(file.original_filename.tr("\x00", '')).gsub(/[^\w.-]/, '_')
    # マジックバイトベースのMIMEタイプ検出を優先
    content_type = Marcel::MimeType.for(file)
    file.rewind
    # 検出できなかった場合のフォールバック
    content_type = file.content_type || detect_content_type(filename) if content_type == 'application/octet-stream'
    {
      filename: filename,
      content_type: content_type,
      file_size: file.size,
      media_type: determine_media_type(content_type, filename)
    }
  end

  def build_media_attachment_with_active_storage(file, file_info, metadata)
    media_attachment = create_media_attachment_record_with_active_storage(file, file_info, metadata)
    media_attachment.save!
    media_attachment
  end

  def create_media_attachment_record_with_active_storage(file, file_info, metadata)
    attrs = {
      file_name: file_info[:filename],
      content_type: file_info[:content_type],
      file_size: file_info[:file_size],
      media_type: file_info[:media_type],
      width: metadata[:width],
      height: metadata[:height],
      blurhash: metadata[:blurhash],
      description: description,
      metadata: metadata.to_json,
      processed: true
    }

    # V2では processing_status を追加
    attrs[:processing_status] = processing_status if processing_status

    media_attachment = user.media_attachments.build(attrs)

    # S3が有効な場合はimg/フォルダに格納
    blob = create_storage_blob(io: file, filename: file.original_filename, content_type: file.content_type, folder: 'img')
    media_attachment.file.attach(blob)

    # 動画の場合はサムネイルもActive Storageに保存
    attach_video_thumbnail(media_attachment, metadata[:thumbnail_path])

    media_attachment
  end

  def attach_video_thumbnail(media_attachment, thumbnail_path)
    return unless thumbnail_path && File.exist?(thumbnail_path) && File.size(thumbnail_path).positive?

    thumb_io = File.open(thumbnail_path, 'rb')
    thumb_blob = create_storage_blob(
      io: thumb_io,
      filename: "thumb_#{File.basename(thumbnail_path)}",
      content_type: 'image/jpeg',
      folder: 'thumb'
    )
    media_attachment.thumbnail.attach(thumb_blob)
  ensure
    thumb_io&.close
    FileUtils.rm_f(thumbnail_path) if thumbnail_path
  end

  def determine_media_type(content_type, filename)
    MediaTypeDetector.determine(content_type, filename)
  end

  def detect_content_type(filename)
    ContentType.from_filename(filename).to_s
  end

  def extract_file_metadata(file, media_type)
    case media_type
    when 'image'
      extract_image_metadata(file)
    when 'video'
      extract_video_metadata(file)
    else
      {}
    end
  end

  def extract_image_metadata(file)
    require 'vips'

    # ファイルの内容を一時的に保存
    temp_file = Tempfile.new(['image', File.extname(file.original_filename)])
    temp_file.binmode
    temp_file.write(file.read)
    temp_file.close
    file.rewind

    # libvipsで画像を読み込み
    image = Vips::Image.new_from_file(temp_file.path)

    {
      width: image.width,
      height: image.height,
      blurhash: generate_blurhash_from_vips(image)
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to extract image metadata with libvips: #{e.message}"
    {}
  ensure
    temp_file&.unlink
  end

  def extract_video_metadata(file)
    require 'tempfile'
    require 'open3'

    with_temp_video_file(file) do |temp_file_path|
      extract_video_info_with_ffprobe(temp_file_path)
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to extract video metadata: #{e.message}"
    { width: 0, height: 0, blurhash: nil }
  end

  def with_temp_video_file(file)
    temp_file = Tempfile.new(['video', File.extname(file.original_filename)])
    temp_file.binmode
    temp_file.write(file.read)
    temp_file.close
    file.rewind

    yield(temp_file.path)
  ensure
    temp_file&.unlink
  end

  def extract_video_info_with_ffprobe(file_path)
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', '-show_format', file_path]
    stdout, stderr, status = Open3.capture3(*cmd)

    if status.success?
      parse_video_info(stdout, file_path)
    else
      Rails.logger.warn "Failed to extract video metadata with ffprobe: #{stderr}"
      { width: 0, height: 0, blurhash: nil }
    end
  end

  def parse_video_info(json_output, file_path)
    require 'json'

    info = JSON.parse(json_output)
    video_stream = info['streams'].find { |stream| stream['codec_type'] == 'video' }

    return { width: 0, height: 0, blurhash: nil } unless video_stream

    width = video_stream['width'].to_i
    height = video_stream['height'].to_i
    duration = Float(info.dig('format', 'duration') || video_stream['duration'], exception: false)
    blurhash, thumbnail_path = extract_blurhash_and_thumbnail(file_path, duration)

    { width: width, height: height, blurhash: blurhash, thumbnail_path: thumbnail_path }
  end

  def extract_blurhash_and_thumbnail(file_path, duration = nil)
    require 'vips'

    thumb_file = Tempfile.new(['thumb', '.jpg'])
    thumb_file.close

    if VideoFrameExtractor.extract(file_path, thumb_file.path, duration: duration)
      image = Vips::Image.new_from_file(thumb_file.path)
      blurhash = generate_blurhash_from_vips(image)
      [blurhash, thumb_file.path]
    else
      [nil, nil]
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to extract video thumbnail: #{e.message}"
    [nil, nil]
  end

  def generate_blurhash_from_vips(image)
    BlurhashGenerator.from_vips(image)
  rescue StandardError => e
    Rails.logger.warn "Failed to generate blurhash with libvips: #{e.message}"
    BlurhashGenerator::PLACEHOLDER
  end
end
