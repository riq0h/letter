# frozen_string_literal: true

require 'marcel'

class RemoteEmojiCopyService
  include HTTParty

  def initialize
    @copied_emojis = []
    @failed_copies = []
  end

  # リモート絵文字をローカルにコピー
  def copy_emoji(remote_emoji)
    return { success: false, error: 'ローカル絵文字はコピーできません' } if remote_emoji.local?

    # 既存のローカル絵文字と重複チェック
    existing_local = CustomEmoji.local.find_by(shortcode: remote_emoji.shortcode)
    return { success: false, error: "ショートコード ':#{remote_emoji.shortcode}:' は既に使用されています" } if existing_local

    # 画像をダウンロードしてローカル絵文字を作成
    begin
      local_emoji = create_local_copy(remote_emoji)
      @copied_emojis << local_emoji

      { success: true, emoji: local_emoji }
    rescue StandardError => e
      error_message = "コピーに失敗しました: #{e.message}"
      @failed_copies << { emoji: remote_emoji, error: error_message }

      { success: false, error: error_message }
    end
  end

  # 複数のリモート絵文字を一括コピー
  def copy_multiple(remote_emoji_ids)
    results = {
      success_count: 0,
      failed_count: 0,
      copied_emojis: [],
      failed_copies: []
    }

    remote_emojis = CustomEmoji.remote.where(id: remote_emoji_ids)

    remote_emojis.each do |emoji|
      result = copy_emoji(emoji)

      if result[:success]
        results[:success_count] += 1
        results[:copied_emojis] << result[:emoji]
      else
        results[:failed_count] += 1
        results[:failed_copies] << { emoji: emoji, error: result[:error] }
      end
    end

    results
  end

  # コピー時のショートコード競合解決
  def copy_with_rename(remote_emoji, new_shortcode = nil)
    return { success: false, error: 'ローカル絵文字はコピーできません' } if remote_emoji.local?

    # 新しいショートコードが指定されていない場合は自動生成
    shortcode = new_shortcode || generate_unique_shortcode(remote_emoji.shortcode)

    # ショートコードの重複チェック
    return { success: false, error: "ショートコード ':#{shortcode}:' は既に使用されています" } if CustomEmoji.local.exists?(shortcode: shortcode)

    begin
      local_emoji = create_local_copy(remote_emoji, shortcode)
      @copied_emojis << local_emoji

      { success: true, emoji: local_emoji }
    rescue StandardError => e
      error_message = "コピーに失敗しました: #{e.message}"
      @failed_copies << { emoji: remote_emoji, error: error_message }

      { success: false, error: error_message }
    end
  end

  attr_reader :copied_emojis, :failed_copies

  private

  def create_local_copy(remote_emoji, custom_shortcode = nil)
    shortcode = custom_shortcode || remote_emoji.shortcode

    # 画像をダウンロード
    image_data = download_image(remote_emoji.image_url)

    # ローカル絵文字を作成
    local_emoji = CustomEmoji.new(
      shortcode: shortcode,
      domain: nil, # ローカル絵文字
      disabled: false,
      visible_in_picker: true,
      category_id: remote_emoji.category_id
    )

    # 画像を添付
    attach_image_to_emoji(local_emoji, image_data, remote_emoji.image_url)

    # 保存実行
    local_emoji.save!

    local_emoji
  rescue StandardError => e
    Rails.logger.error "Failed to create local copy of emoji :#{remote_emoji.shortcode}: #{e.message}"
    raise "Failed to create local copy: #{e.message}"
  end

  def download_image(image_url)
    response = HTTParty.get(image_url, timeout: 30, follow_redirects: true)

    raise "Failed to download image: HTTP #{response.code}" unless response.success?

    raise "Invalid content type: #{response.headers['content-type']}" unless response.headers['content-type']&.start_with?('image/')

    # ファイルサイズ制限（5MB）
    raise "Image too large: #{response.body.bytesize} bytes" if response.body.bytesize > 5.megabytes

    response.body
  rescue StandardError => e
    Rails.logger.error "Image download failed for #{image_url}: #{e.message}"
    raise "画像のダウンロードに失敗しました: #{e.message}"
  end

  def attach_image_to_emoji(emoji, image_data, original_url)
    content_type = detect_content_type(image_data)
    extension = determine_file_extension(content_type, original_url)
    filename = "#{emoji.shortcode}#{extension}"

    attach_image_file(emoji, image_data, filename, content_type)
  rescue StandardError => e
    Rails.logger.error "Failed to attach image to emoji: #{e.message}"
    raise "画像の添付に失敗しました: #{e.message}"
  end

  def detect_content_type(image_data)
    Marcel::MimeType.for(StringIO.new(image_data))
  end

  def determine_file_extension(content_type, original_url)
    case content_type
    when 'image/jpeg', 'image/jpg'
      '.jpg'
    when 'image/png'
      '.png'
    when 'image/gif'
      '.gif'
    when 'image/webp'
      '.webp'
    else
      extract_extension_from_url(original_url)
    end
  end

  def extract_extension_from_url(url)
    uri = begin
      URI.parse(url)
    rescue StandardError
      nil
    end

    if uri&.path
      File.extname(uri.path).downcase
    else
      '.png' # デフォルト
    end
  end

  def attach_image_file(emoji, image_data, filename, content_type)
    emoji.attach_image_with_folder(
      io: StringIO.new(image_data),
      filename: filename,
      content_type: content_type
    )
  end

  def generate_unique_shortcode(base_shortcode)
    counter = 1
    loop do
      candidate = "#{base_shortcode}_#{counter}"
      return candidate unless CustomEmoji.local.exists?(shortcode: candidate)

      counter += 1

      # 無限ループ防止
      raise 'Could not generate unique shortcode' if counter > 1000
    end
  end
end
