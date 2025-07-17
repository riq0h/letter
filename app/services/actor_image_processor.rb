# frozen_string_literal: true

require 'image_processing/mini_magick'

class ActorImageProcessor
  AVATAR_SIZE = 400
  AVATAR_THUMBNAIL_SIZE = 48

  def initialize(actor)
    @actor = actor
  end

  def attach_avatar_with_folder(io:, filename:, content_type:)
    processed_io = process_avatar_image(io)

    if ENV['S3_ENABLED'] == 'true'
      custom_key = "img/#{SecureRandom.hex(16)}"
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
      custom_key = "img/#{SecureRandom.hex(16)}"
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

    pipeline = ImageProcessing::MiniMagick.source(io)

    processed = pipeline
                .resize_to_fill(AVATAR_SIZE, AVATAR_SIZE)
                .convert('png')
                .call

    File.open(processed.path, 'rb')
  end

  def distribute_profile_update_after_image_change(image_type)
    return unless actor.local?

    Rails.logger.info "🖼️ #{image_type.capitalize} updated for #{actor.username}, distributing profile update"
    ActorActivityDistributor.new(actor).distribute_profile_update_for_image_change
  rescue StandardError => e
    Rails.logger.error "Failed to distribute profile update after #{image_type} change: #{e.message}"
  end
end
