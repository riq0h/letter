# frozen_string_literal: true

require 'vips'
require 'net/http'
require 'digest'

class ActorImageProcessor
  include SsrfProtection
  include BlobStorage

  AVATAR_SIZE = 400
  AVATAR_THUMBNAIL_SIZE = 48

  def initialize(actor)
    @actor = actor
  end

  def attach_avatar_with_folder(io:, filename:, content_type:)
    processed_io = process_avatar_image(io)

    blob = create_storage_blob(io: processed_io, filename: filename, content_type: content_type, folder: 'avatar')
    actor.avatar.attach(blob)

    # アバター更新をActivityPubで配信
    distribute_profile_update_after_image_change('avatar')
  end

  def attach_header_with_folder(io:, filename:, content_type:)
    blob = create_storage_blob(io: io, filename: filename, content_type: content_type, folder: 'header')
    actor.header.attach(blob)

    # ヘッダ更新をActivityPubで配信
    distribute_profile_update_after_image_change('header')
  end

  def avatar_url(skip_accessibility_check: false)
    # アバターが添付されている場合はActiveStorageから取得（ローカル・外部問わず）
    if actor.avatar.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{actor.avatar.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(actor.avatar)
      end
    else
      # アバターが添付されていない場合はraw_dataから取得を試み、可用性をチェック
      remote_avatar_url = actor.extract_remote_image_url('icon')
      if remote_avatar_url.present?
        # キャッシュされた可用性結果をチェック
        if skip_accessibility_check || remote_image_accessible_cached?(remote_avatar_url)
          remote_avatar_url
        else
          default_avatar_url
        end
      else
        default_avatar_url
      end
    end
  rescue StandardError
    default_avatar_url
  end

  def header_url
    # ヘッダーが添付されている場合はActiveStorageから取得（ローカル・外部問わず）
    if actor.header.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{actor.header.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(actor.header)
      end
    else
      # ヘッダーが添付されていない場合のみraw_dataから取得
      actor.extract_remote_image_url('image')
    end
  rescue StandardError
    nil
  end

  private

  attr_reader :actor

  def default_avatar_url
    "#{Rails.application.config.activitypub.base_url}/icon.png"
  end

  def process_avatar_image(io)
    io.rewind

    # 一時ファイルに保存
    temp_input = Tempfile.new(['avatar_input', '.tmp'])
    temp_input.binmode
    temp_input.write(io.read)
    temp_input.close
    io.rewind

    # libvipsで画像を読み込み
    image = Vips::Image.new_from_file(temp_input.path)

    # リサイズ（crop to fill）
    # まず適切な倍率でリサイズしてから中央をクロップ
    scale = [AVATAR_SIZE.to_f / image.width, AVATAR_SIZE.to_f / image.height].max
    resized = image.resize(scale)

    # 中央から正方形をクロップ
    left = [(resized.width - AVATAR_SIZE) / 2, 0].max
    top = [(resized.height - AVATAR_SIZE) / 2, 0].max
    cropped = resized.extract_area(left, top, AVATAR_SIZE, AVATAR_SIZE)

    # 出力用一時ファイル
    temp_output = Tempfile.new(['avatar_output', '.png'])
    temp_output.close

    # PNGとして保存
    cropped.write_to_file(temp_output.path)

    File.open(temp_output.path, 'rb')
  rescue StandardError => e
    Rails.logger.warn "Failed to process avatar image with libvips: #{e.message}"
    # 元の画像をそのまま返す
    io.rewind
    io
  ensure
    temp_input&.unlink
    temp_output&.unlink
  end

  def distribute_profile_update_after_image_change(image_type)
    return unless actor.local?

    Rails.logger.info "🖼️ #{image_type.capitalize} updated for #{actor.username}, distributing profile update"
    ActorActivityDistributor.new(actor).distribute_profile_update_for_image_change
  rescue StandardError => e
    Rails.logger.error "Failed to distribute profile update after #{image_type} change: #{e.message}"
  end

  # キャッシュされた可用性チェック
  def remote_image_accessible_cached?(url)
    return false if url.blank?

    cache_key = "avatar_accessibility:#{Digest::SHA256.hexdigest(url)}"

    # キャッシュから結果を取得（24時間キャッシュ）
    cached_result = Rails.cache.read(cache_key)
    return cached_result unless cached_result.nil?

    # キャッシュされていない場合は実際にチェックしてキャッシュ
    accessible = remote_image_accessible?(url)
    Rails.cache.write(cache_key, accessible, expires_in: 24.hours)
    accessible
  end

  # リモート画像の可用性をチェック
  def remote_image_accessible?(url)
    return false if url.blank?
    return false unless validate_url_for_ssrf!(url)

    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'
    http.open_timeout = 3
    http.read_timeout = 5

    request = Net::HTTP::Head.new(uri)
    request['User-Agent'] = InstanceConfig.user_agent

    response = http.request(request)
    # 2xx (成功) または 3xx (リダイレクト) を有効とみなす
    (200..399).cover?(response.code.to_i)
  rescue StandardError => e
    Rails.logger.warn "Failed to check remote image accessibility for #{url}: #{e.message}"
    false
  end
end
