# frozen_string_literal: true

# URLからファイル名を抽出するValueObject
# URLの構造を解析し、適切なファイル名を生成
class UrlFilename
  DEFAULT_FILENAME = 'download'
  MAX_FILENAME_LENGTH = 255

  attr_reader :url, :filename, :extension

  def initialize(url)
    @url = url.to_s.strip
    @filename, @extension = extract_filename_and_extension
    freeze
  end

  # ファクトリメソッド
  def self.from_url(url)
    new(url)
  end

  # 拡張子付きのファイル名を取得
  def full_filename
    return filename if extension.blank?

    "#{filename}.#{extension}"
  end

  # ファイル名が有効かどうか
  def valid?
    filename.present? && filename != DEFAULT_FILENAME
  end

  # URLが有効かどうか
  def valid_url?
    url.present? && url.match?(/\Ahttps?:\/\//)
  end

  # 文字列表現
  def to_s
    full_filename
  end

  # 等価性の判定
  def ==(other)
    return false unless other.is_a?(UrlFilename)

    url == other.url
  end

  alias eql? ==

  delegate :hash, to: :url

  private

  def extract_filename_and_extension
    return [DEFAULT_FILENAME, nil] unless valid_url?

    uri = parse_uri
    return [DEFAULT_FILENAME, nil] unless uri

    path = uri.path
    return [DEFAULT_FILENAME, nil] if path.blank? || path == '/'

    # パスからファイル名部分を抽出
    basename = File.basename(path)
    return [DEFAULT_FILENAME, nil] if basename.blank? || basename == '.'

    # クエリパラメータを除去
    filename_without_query = basename.split('?').first
    return [DEFAULT_FILENAME, nil] if filename_without_query.blank?

    # ファイル名をサニタイズ
    sanitized = sanitize_filename(filename_without_query)

    # サニタイズで空になった場合はデフォルトを使用
    return [DEFAULT_FILENAME, nil] if sanitized.nil?

    # 拡張子を分離
    if sanitized.include?('.')
      parts = sanitized.split('.')
      extension = parts.pop if parts.length > 1
      filename = parts.join('.')
    else
      filename = sanitized
      extension = nil
    end

    # ファイル名が空の場合はデフォルトを使用
    filename = DEFAULT_FILENAME if filename.blank?

    # 長さ制限を適用
    filename = truncate_filename(filename, extension)

    [filename, extension]
  end

  def parse_uri
    URI.parse(url)
  rescue URI::InvalidURIError
    nil
  end

  def sanitize_filename(filename)
    # 危険な文字を除去（ただし、サニタイズ後も何らかの文字が残るように）
    sanitized = filename.gsub(/[^\w\-_.]/, '_')

    # 連続するアンダースコアを1つにまとめる
    sanitized = sanitized.squeeze('_')

    # 前後のアンダースコアを除去
    sanitized = sanitized.gsub(/\A_+|_+\z/, '')

    # 空になった場合はnilを返す（デフォルトファイル名が使われる）
    sanitized.presence
  end

  def truncate_filename(filename, extension)
    return filename if filename.length <= MAX_FILENAME_LENGTH

    # 拡張子の長さを考慮して切り詰め
    extension_length = extension&.length || 0
    max_base_length = MAX_FILENAME_LENGTH - extension_length - 1 # ドット分も差し引く

    filename[0, max_base_length]
  end
end
