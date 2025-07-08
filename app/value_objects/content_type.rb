# frozen_string_literal: true

# MIMEタイプの検出を行うValueObject
# ファイル拡張子からMIMEタイプを決定し、サポートされているメディアタイプを管理
class ContentType
  MIME_TYPES = {
    # 画像
    '.jpg' => 'image/jpeg',
    '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.heic' => 'image/heic',
    '.heif' => 'image/heif',
    '.avif' => 'image/avif',

    # ビデオ
    '.mp4' => 'video/mp4',
    '.webm' => 'video/webm',
    '.mov' => 'video/quicktime',
    '.ogg' => 'video/ogg',
    '.ogv' => 'video/ogg',

    # オーディオ
    '.mp3' => 'audio/mpeg',
    '.oga' => 'audio/ogg',
    '.wav' => 'audio/wave',
    '.flac' => 'audio/flac',
    '.opus' => 'audio/opus',
    '.weba' => 'audio/webm',
    '.m4a' => 'audio/mp4'
  }.freeze

  SUPPORTED_IMAGE_TYPES = %w[
    image/jpeg image/png image/gif image/webp
    image/heic image/heif image/avif
  ].freeze

  SUPPORTED_VIDEO_TYPES = %w[
    video/mp4 video/webm video/quicktime video/ogg
  ].freeze

  SUPPORTED_AUDIO_TYPES = %w[
    audio/mpeg audio/mp3 audio/ogg audio/vorbis
    audio/wave audio/wav audio/x-wav audio/x-pn-wave
    audio/flac audio/opus audio/webm audio/mp4
  ].freeze

  DEFAULT_MIME_TYPE = 'application/octet-stream'

  attr_reader :mime_type, :filename

  def initialize(mime_type, filename = nil)
    @mime_type = mime_type.to_s
    @filename = filename.to_s
    freeze
  end

  # ファイル名からContentTypeを作成
  def self.from_filename(filename)
    mime_type = detect_mime_type(filename)
    new(mime_type, filename)
  end

  # MIMEタイプから直接作成
  def self.from_mime_type(mime_type)
    new(mime_type)
  end

  # MIMEタイプが画像かどうか
  def image?
    SUPPORTED_IMAGE_TYPES.include?(mime_type)
  end

  # MIMEタイプが動画かどうか
  def video?
    SUPPORTED_VIDEO_TYPES.include?(mime_type)
  end

  # MIMEタイプが音声かどうか
  def audio?
    SUPPORTED_AUDIO_TYPES.include?(mime_type)
  end

  # サポートされているメディアタイプかどうか
  def supported?
    image? || video? || audio?
  end

  # 文字列表現
  def to_s
    mime_type
  end

  # 等価性の判定
  def ==(other)
    return false unless other.is_a?(ContentType)

    mime_type == other.mime_type
  end

  alias eql? ==

  delegate :hash, to: :mime_type

  # サポートされているすべてのMIMEタイプを取得
  def self.supported_mime_types
    SUPPORTED_IMAGE_TYPES + SUPPORTED_VIDEO_TYPES + SUPPORTED_AUDIO_TYPES
  end

  # 画像のMIMEタイプを取得
  def self.supported_image_types
    SUPPORTED_IMAGE_TYPES
  end

  # 動画のMIMEタイプを取得
  def self.supported_video_types
    SUPPORTED_VIDEO_TYPES
  end

  # 音声のMIMEタイプを取得
  def self.supported_audio_types
    SUPPORTED_AUDIO_TYPES
  end

  class << self
    private

    def detect_mime_type(filename)
      return DEFAULT_MIME_TYPE if filename.blank?

      extension = File.extname(filename).downcase
      MIME_TYPES[extension] || DEFAULT_MIME_TYPE
    end
  end
end
