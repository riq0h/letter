# frozen_string_literal: true

require 'vips'

class ActorImageProcessor
  AVATAR_SIZE = 400
  AVATAR_THUMBNAIL_SIZE = 48

  def initialize(actor)
    @actor = actor
  end

  def attach_avatar_with_folder(io:, filename:, content_type:)
    processed_io = process_avatar_image(io)

    if ENV['S3_ENABLED'] == 'true'
      custom_key = "avatar/#{SecureRandom.hex(16)}"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: processed_io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
      actor.avatar.attach(blob)
    else
      actor.avatar.attach(io: processed_io, filename: filename, content_type: content_type)
    end

    # アバター更新をActivityPubで配信
    distribute_profile_update_after_image_change('avatar')
  end

  def attach_header_with_folder(io:, filename:, content_type:)
    if ENV['S3_ENABLED'] == 'true'
      custom_key = "header/#{SecureRandom.hex(16)}"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
      actor.header.attach(blob)
    else
      actor.header.attach(io: io, filename: filename, content_type: content_type)
    end

    # ヘッダ更新をActivityPubで配信
    distribute_profile_update_after_image_change('header')
  end

  def avatar_url
    # ローカルユーザの場合はActiveStorageから取得
    if actor.local? && actor.avatar.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{actor.avatar.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(actor.avatar)
      end
    else
      # 外部ユーザの場合はraw_dataから取得
      actor.extract_remote_image_url('icon')
    end
  end

  def header_url
    # ローカルユーザの場合はActiveStorageから取得
    if actor.local? && actor.header.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{actor.header.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(actor.header)
      end
    else
      # 外部ユーザの場合はraw_dataから取得
      actor.extract_remote_image_url('image')
    end
  rescue StandardError
    nil
  end

  private

  attr_reader :actor

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
end
