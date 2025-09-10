# frozen_string_literal: true

class MediaAttachment < ApplicationRecord
  include RemoteLocalHelper

  # === 定数 ===
  MEDIA_TYPES = %w[image video audio document].freeze
  IMAGE_FORMATS = %w[jpeg jpg png gif webp avif].freeze
  VIDEO_FORMATS = %w[mp4 webm mov avi].freeze
  AUDIO_FORMATS = %w[mp3 ogg wav flac m4a].freeze
  DOCUMENT_FORMATS = %w[pdf txt doc docx].freeze

  MAX_IMAGE_SIZE = 50.megabytes
  MAX_VIDEO_SIZE = 500.megabytes
  MAX_AUDIO_SIZE = 250.megabytes
  MAX_DOCUMENT_SIZE = 100.megabytes

  # 浮動小数点比較用の許容範囲
  FLOAT_TOLERANCE = 0.01

  # === バリデーション ===
  validates :media_type, presence: true, inclusion: { in: MEDIA_TYPES }
  validates :remote_url, presence: true, unless: :local_file?
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  validates :content_type, presence: true
  validates :file_name, presence: true

  validate :validate_file_size_by_type
  validate :validate_mime_type_by_media_type

  # === アソシエーション ===
  belongs_to :actor, inverse_of: :media_attachments
  belongs_to :object, optional: true, inverse_of: :media_attachments, class_name: 'ActivityPubObject', primary_key: :id

  # Active Storage統合
  has_one_attached :file

  # カスタムアップロードメソッド（フォルダ構造対応）
  def attach_file_with_folder(io:, filename:, content_type:)
    if ENV['S3_ENABLED'] == 'true'
      custom_key = "img/#{SecureRandom.hex(16)}"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
      file.attach(blob)
    else
      file.attach(io: io, filename: filename, content_type: content_type)
    end
  end

  # === スコープ ===
  scope :images, -> { where(media_type: 'image') }
  scope :videos, -> { where(media_type: 'video') }
  scope :audio, -> { where(media_type: 'audio') }
  scope :documents, -> { where(media_type: 'document') }
  scope :attached, -> { where.not(object_id: nil) }
  scope :unattached, -> { where(object_id: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # === コールバック ===
  before_validation :set_defaults, on: :create
  before_validation :extract_metadata

  # === 判定メソッド ===

  def image?
    media_type == 'image'
  end

  def video?
    media_type == 'video'
  end

  def audio?
    media_type == 'audio'
  end

  def document?
    media_type == 'document'
  end

  def attached?
    object_id.present?
  end

  delegate :local?, to: :actor

  # === 表示用メソッド ===

  def display_name
    file_name.presence || 'Untitled'
  end

  def file_extension
    return '' if file_name.blank?

    File.extname(file_name).downcase.delete('.')
  end

  def human_file_size
    return '0 B' if file_size.zero?

    units = %w[B KB MB GB TB]
    size = file_size.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(1)} #{units[unit_index]}"
  end

  def preview_url
    if video? && file.attached?
      # 動画の場合は1秒目のフレームを取得（libvipsを使用）
      generate_video_preview_url
    elsif file.attached?
      # 画像の場合はそのまま表示
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{file.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(file)
      end
    elsif image? && remote_url.present?
      # リモート画像の場合
      remote_url
    else
      # デフォルトのプレビューアイコン
      default_preview_icon_url
    end
  end

  private

  def generate_video_preview_url
    return default_preview_icon_url unless file.attached?

    # FFmpegで1秒目のフレームを抽出してBase64エンコード
    Rails.cache.fetch("video_preview_#{id}", expires_in: 1.week) do
      extract_video_frame_as_data_url || default_preview_icon_url
    end
  rescue StandardError => e
    Rails.logger.error "Failed to generate video preview for #{id}: #{e.message}"
    default_preview_icon_url
  end

  def extract_video_frame_as_data_url
    require 'tempfile'
    require 'open3'
    require 'base64'

    # 入力動画ファイル
    input_file = Tempfile.new(['input_video', File.extname(file_name)])
    input_file.binmode
    input_file.write(file.download)
    input_file.close

    # 出力サムネイルファイル
    output_file = Tempfile.new(['thumbnail', '.jpg'])
    output_file.close

    # FFmpeg コマンド
    cmd = [
      'ffmpeg',
      '-i', input_file.path,
      '-ss', '00:00:01',
      '-vframes', '1',
      '-q:v', '2',
      '-y',
      output_file.path
    ]

    _, stderr, status = Open3.capture3(*cmd)

    if status.success? && File.exist?(output_file.path) && File.size(output_file.path).positive?
      # Base64エンコードしてdata URLとして返す
      image_data = File.binread(output_file.path)
      "data:image/jpeg;base64,#{Base64.strict_encode64(image_data)}"
    else
      Rails.logger.error "FFmpeg failed: #{stderr}"
      nil
    end
  ensure
    input_file&.unlink
    output_file&.unlink
  end

  # Active Storageファイルまたはリモートファイルの公開URL
  def url
    if file.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{file.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(file)
      end
    else
      remote_url
    end
  end

  # キャッシュされたリモート画像のURLを取得（キャッシュが有効な場合）
  def cached_url
    return url if file.attached? || remote_url.blank?

    # リモート画像のキャッシュされたURLを取得
    RemoteImageCacheService.get_cached_image_url(remote_url)
  end

  # リモート画像をキャッシュに保存
  def cache_remote_image
    return false if file.attached? || remote_url.blank?

    cached_url = RemoteImageCacheService.cache_remote_image(remote_url, self)
    cached_url != remote_url # キャッシュに成功した場合はtrue
  end

  # ローカルファイルかどうかの判定
  def local_file?
    file.attached?
  end

  # ローカルストレージのファイルパス（MediaController用）
  def storage_path
    return nil unless file.attached?

    # Active Storageのblobキーを使用してファイルパスを生成
    # ローカルストレージサービス使用時のパス形式: xx/xx/xxxxxxxxxxxxxxxxxxxx
    blob_key = file.blob.key
    "#{blob_key[0, 2]}/#{blob_key[2, 2]}/#{blob_key}"
  end

  def aspect_ratio
    return nil unless width.present? && height.present? && height.positive?

    (width.to_f / height).round(2)
  end

  def landscape?
    return false unless aspect_ratio

    aspect_ratio > 1.0
  end

  def portrait?
    return false unless aspect_ratio

    aspect_ratio < 1.0
  end

  def square?
    return false unless aspect_ratio

    # 浮動小数点の安全な比較
    (aspect_ratio - 1.0).abs < FLOAT_TOLERANCE
  end

  # === ActivityPub関連メソッド ===

  def activitypub_document
    {
      type: 'Document',
      mediaType: content_type,
      url: url, # Active StorageのURLまたはremote_urlを使用
      name: description.presence || display_name,
      width: width,
      height: height
    }.tap do |doc|
      doc[:summary] = description if description.present?
    end
  end

  def set_defaults
    self.processed = false if processed.nil?
    self.blurhash ||= generate_placeholder_blurhash
  end

  def extract_metadata
    # Active Storageファイルがアタッチされている場合
    if file.attached?
      extract_metadata_from_file
    elsif remote_url.present? && !processed?
      extract_metadata_from_remote_url
    end
  end

  def extract_metadata_from_file
    return unless file.attached?

    set_basic_file_attributes
    detect_media_type_from_filename if media_type.blank?
    mark_as_processed
  end

  def set_basic_file_attributes
    self.file_name ||= file.filename.to_s
    self.content_type ||= file.content_type
    self.file_size ||= file.byte_size
  end

  def mark_as_processed
    self.processed = true
  end

  def extract_metadata_from_remote_url
    # ファイル拡張子からmedia_typeを推測
    detect_media_type_from_filename if media_type.blank?

    # 基本的なメタデータ設定
    self.processed = true
  end

  def detect_media_type_from_filename
    ext = file_extension

    self.media_type = determine_media_type_by_extension(ext)
  end

  def determine_media_type_by_extension(ext)
    return 'image' if IMAGE_FORMATS.include?(ext)
    return 'video' if VIDEO_FORMATS.include?(ext)
    return 'audio' if AUDIO_FORMATS.include?(ext)
    return 'document' if DOCUMENT_FORMATS.include?(ext)

    'document'
  end

  def validate_file_size_by_type
    max_size = max_size_for_media_type

    return unless file_size > max_size

    errors.add(:file_size, "is too large for #{media_type} files (max: #{max_size / 1.megabyte}MB)")
  end

  def max_size_for_media_type
    case media_type
    when 'image'
      MAX_IMAGE_SIZE
    when 'video'
      MAX_VIDEO_SIZE
    when 'audio'
      MAX_AUDIO_SIZE
    else
      MAX_DOCUMENT_SIZE
    end
  end

  def validate_mime_type_by_media_type
    valid_formats = valid_formats_for_media_type

    return if valid_formats.empty?

    # MIME typeから拡張子を抽出してチェック
    format_from_mime = content_type.split('/').last

    return if valid_formats.include?(format_from_mime)

    errors.add(:content_type, "#{content_type} is not supported for #{media_type} files")
  end

  def valid_formats_for_media_type
    case media_type
    when 'image'
      IMAGE_FORMATS
    when 'video'
      VIDEO_FORMATS
    when 'audio'
      AUDIO_FORMATS
    else
      DOCUMENT_FORMATS
    end
  end

  def default_preview_icon_url
    case media_type
    when 'video'
      '/icons/video-preview.svg'
    when 'audio'
      '/icons/audio-preview.svg'
    when 'document'
      '/icons/document-preview.svg'
    else
      '/icons/file-preview.svg'
    end
  end

  def generate_placeholder_blurhash
    # プレースホルダーとして単色のblurhashを生成
    case media_type
    when 'image'
      'L6PZfSi_.AyE_3t7t7R**0o#DgR4' # 薄いグレー
    when 'video'
      'L4R:8|00fQ00fQfQfQfQfQfQfQfQ' # 濃いグレー
    else
      'L2N]?U00Rj00RjRjRjRjRjRjRjRj' # 黒
    end
  end
end
