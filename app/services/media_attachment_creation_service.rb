# frozen_string_literal: true

class MediaAttachmentCreationService
  def initialize(user:, description: nil, processing_status: nil)
    @user = user
    @description = description
    @processing_status = processing_status
  end

  def create_from_file(file)
    file_info = extract_file_info(file)
    metadata = extract_file_metadata(file, file_info[:media_type])

    build_media_attachment_with_active_storage(file, file_info, metadata)
  end

  private

  attr_reader :user, :description, :processing_status

  def extract_file_info(file)
    filename = file.original_filename
    content_type = file.content_type || detect_content_type(filename)
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
    if ENV['S3_ENABLED'] == 'true'
      custom_key = "img/#{SecureRandom.hex(16)}"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
      media_attachment.file.attach(blob)
    else
      media_attachment.file.attach(file)
    end

    media_attachment
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
    cmd = ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_streams', file_path]
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
    blurhash = extract_blurhash_from_video(file_path)

    { width: width, height: height, blurhash: blurhash }
  end

  def extract_blurhash_from_video(file_path)
    require 'vips'

    thumb_file = Tempfile.new(['thumb', '.jpg'])
    thumb_file.close

    thumb_cmd = ['ffmpeg', '-i', file_path, '-ss', '00:00:01', '-vframes', '1', '-q:v', '2', '-y', thumb_file.path]
    _, _, thumb_status = Open3.capture3(*thumb_cmd)

    if thumb_status.success? && File.exist?(thumb_file.path)
      image = Vips::Image.new_from_file(thumb_file.path)
      generate_blurhash_from_vips(image)
    end
  ensure
    thumb_file&.unlink
  end

  def generate_blurhash_from_vips(image)
    require 'blurhash'

    # libvipsの画像をRGB形式に変換し、適切なサイズにリサイズ
    # Blurhashは小さい画像で十分なので、最大128x128にリサイズ
    max_size = 128
    if image.width > max_size || image.height > max_size
      scale = [max_size.to_f / image.width, max_size.to_f / image.height].min
      image = image.resize(scale)
    end

    # RGB形式に変換（アルファチャンネルがある場合は削除）
    image = image.colourspace('srgb') unless image.interpretation == :srgb
    image = image.extract_band(0, n: 3) if image.bands > 3

    # ピクセルデータを取得
    pixel_data = image.write_to_memory

    # バイトデータを整数配列に変換
    pixels = pixel_data.unpack('C*')

    Blurhash.encode(image.width, image.height, pixels, x_components: 4, y_components: 4)
  rescue StandardError => e
    Rails.logger.warn "Failed to generate blurhash with libvips: #{e.message}"
    'LEHV6nWB2yk8pyo0adR*.7kCMdnj'
  end
end
