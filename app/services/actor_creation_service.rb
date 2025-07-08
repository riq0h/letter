# frozen_string_literal: true

require 'net/http'
require 'stringio'

# リモートアクターの作成を担当するサービス
class ActorCreationService
  require_relative 'concerns/actor_attachment_processing'
  include ActorAttachmentProcessing

  def self.create_from_activitypub_data(actor_data)
    new.create_from_activitypub_data(actor_data)
  end

  def create_from_activitypub_data(actor_data)
    actor = Actor.create!(build_actor_attributes(actor_data))

    # アバターとヘッダー画像を非同期で添付
    attach_remote_images(actor, actor_data)

    actor
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create remote actor: #{e.message}"
    nil
  end

  private

  def build_actor_attributes(actor_data)
    {
      **basic_actor_attributes(actor_data),
      **activitypub_urls(actor_data),
      **actor_metadata(actor_data)
    }
  end

  def basic_actor_attributes(actor_data)
    {
      username: actor_data['preferredUsername'],
      domain: URI.parse(actor_data['id']).host,
      display_name: actor_data['name'],
      note: actor_data['summary'],
      ap_id: actor_data['id'],
      local: false
    }
  end

  def activitypub_urls(actor_data)
    {
      inbox_url: actor_data['inbox'],
      outbox_url: actor_data['outbox'],
      followers_url: actor_data['followers'],
      following_url: actor_data['following'],
      public_key: actor_data.dig('publicKey', 'publicKeyPem')
    }
  end

  def actor_metadata(actor_data)
    {
      actor_type: actor_data['type'] || 'Person',
      discoverable: actor_data['discoverable'],
      manually_approves_followers: actor_data['manuallyApprovesFollowers'],
      raw_data: actor_data.to_json,
      fields: extract_fields_from_attachments(actor_data).to_json
    }
  end

  def attach_remote_images(actor, actor_data)
    # アバター画像を添付
    if (avatar_url = actor_data.dig('icon', 'url'))
      attach_remote_image(actor, :avatar, avatar_url)
    end

    # ヘッダー画像を添付
    if (header_url = actor_data.dig('image', 'url'))
      attach_remote_image(actor, :header, header_url)
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to attach images for actor #{actor.ap_id}: #{e.message}"
  end

  def attach_remote_image(actor, attachment_name, image_url)
    return if image_url.blank?

    response = fetch_image_response(image_url)
    return unless response

    content_type, filename = extract_image_metadata(response, image_url)
    attach_image_to_actor(actor, attachment_name, response.body, filename, content_type)
  rescue StandardError => e
    Rails.logger.warn "Failed to attach #{attachment_name} for actor #{actor.ap_id}: #{e.message}"
  end

  def fetch_image_response(image_url)
    response = Net::HTTP.get_response(URI(image_url))
    response.is_a?(Net::HTTPSuccess) ? response : nil
  end

  def extract_image_metadata(response, image_url)
    content_type = response['content-type'] || 'application/octet-stream'
    filename = File.basename(URI(image_url).path).presence || 'image'
    filename = add_extension_if_needed(filename, content_type)
    [content_type, filename]
  end

  def add_extension_if_needed(filename, content_type)
    return filename if filename.include?('.')

    extension = determine_extension(content_type)
    "#{filename}#{extension}"
  end

  def determine_extension(content_type)
    case content_type
    when /jpeg/ then '.jpg'
    when /png/ then '.png'
    when /gif/ then '.gif'
    when /webp/ then '.webp'
    else '.bin'
    end
  end

  def attach_image_to_actor(actor, attachment_name, image_data, filename, content_type)
    actor.public_send(attachment_name).attach(
      io: StringIO.new(image_data),
      filename: filename,
      content_type: content_type
    )
  end
end
