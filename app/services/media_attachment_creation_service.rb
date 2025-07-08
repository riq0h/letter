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
    media_attachment.file.attach(file)
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
    require 'mini_magick'
    image = MiniMagick::Image.read(file.read)
    file.rewind

    {
      width: image.width,
      height: image.height,
      blurhash: generate_blurhash(image)
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to extract image metadata: #{e.message}"
    {}
  end

  def extract_video_metadata(file)
    require 'mini_magick'

    # 一時ファイルに保存
    temp_file = Tempfile.new(['video', File.extname(file.original_filename)])
    temp_file.binmode
    temp_file.write(file.read)
    temp_file.close
    file.rewind

    # ImageMagickでビデオの最初のフレーム（[0]）を取得
    image = MiniMagick::Image.new("#{temp_file.path}[0]")

    {
      width: image.width,
      height: image.height,
      blurhash: generate_blurhash(image)
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to extract video metadata: #{e.message}"
    { width: 0, height: 0, blurhash: nil }
  ensure
    temp_file&.unlink
  end

  def generate_blurhash(image)
    require 'blurhash'

    pixels = image.get_pixels
    width = image.width
    height = image.height

    pixel_data = pixels.flatten.map(&:to_i)

    Blurhash.encode(width, height, pixel_data, x_components: 4, y_components: 4)
  rescue StandardError => e
    Rails.logger.warn "Failed to generate blurhash: #{e.message}"
    'LEHV6nWB2yk8pyo0adR*.7kCMdnj'
  end
end
