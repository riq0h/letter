# frozen_string_literal: true

require 'net/http'
require 'stringio'
require_relative 'concerns/actor_attachment_processing'

class FollowService
  include ActivityPubHelper
  include ActorAttachmentProcessing

  def initialize(actor)
    @actor = actor
  end

  # リモートまたはローカルアクターをフォロー
  def follow!(target_actor_uri_or_actor, options = {})
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return nil unless target_actor

    # 既にフォロー中か確認
    existing_follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return existing_follow if existing_follow

    # フォロー関係を作成
    follow = create_follow_relationship(target_actor, options)

    # 対象がリモートの場合ActivityPubフォローアクティビティを送信
    send_follow_activity(follow) if target_actor.domain.present?

    follow
  end

  # アクターのフォローを解除
  def unfollow!(target_actor_uri_or_actor)
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return false unless target_actor

    follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return false unless follow

    follow.unfollow!
    true
  end

  private

  def resolve_target_actor(target_actor_uri_or_actor)
    case target_actor_uri_or_actor
    when Actor
      target_actor_uri_or_actor
    when String
      if target_actor_uri_or_actor.match?(/^https?:\/\//)
        # ActivityPub URI
        fetch_remote_actor_by_uri(target_actor_uri_or_actor)
      else
        # @username@domain形式を処理
        username, domain = parse_acct(target_actor_uri_or_actor)
        find_or_fetch_actor(username, domain)
      end
    end
  end

  def parse_acct(acct)
    AccountIdentifierParser.parse_acct(acct)
  end

  def find_or_fetch_actor(username, domain)
    if domain.nil?
      # ローカルアクター
      Actor.find_by(username: username, local: true)
    else
      # リモートアクター - 既存を検索または新規取得
      existing_actor = Actor.find_by(username: username, domain: domain)
      return existing_actor if existing_actor

      # WebFingerを使用してリモートから取得
      fetch_remote_actor(username, domain)
    end
  end

  def fetch_remote_actor(username, domain)
    webfinger_uri = AccountIdentifierParser.build_webfinger_uri(username, domain)
    webfinger_service = WebFingerService.new

    actor_data = webfinger_service.fetch_actor_data(webfinger_uri)
    return nil unless actor_data

    create_remote_actor_from_data(actor_data)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch remote actor #{username}@#{domain}: #{e.message}"
    nil
  end

  def fetch_remote_actor_by_uri(uri)
    # ActivityPub URIから直接アクターデータを取得
    response = fetch_activitypub_object(uri)
    return nil unless response

    create_remote_actor_from_data(response)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch actor from URI #{uri}: #{e.message}"
    nil
  end

  def create_remote_actor_from_data(actor_data)
    actor = Actor.create!(build_actor_attributes(actor_data))

    # アバターとヘッダー画像を非同期で添付
    attach_remote_images(actor, actor_data)

    actor
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create remote actor: #{e.message}"
    nil
  end

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

  def create_follow_relationship(target_actor, _options = {})
    follow_id = Letter::Snowflake.generate
    follow_params = {
      id: follow_id,
      actor: @actor,
      target_actor: target_actor,
      ap_id: generate_follow_ap_id(target_actor, follow_id),
      follow_activity_ap_id: generate_follow_ap_id(target_actor, follow_id)
    }

    # ローカルフォローは承認不要の場合は自動承認
    if target_actor.local?
      follow_params[:accepted] = !target_actor.manually_approves_followers
      follow_params[:accepted_at] = Time.current if follow_params[:accepted]
    else
      # リモートフォローは保留状態で開始
      follow_params[:accepted] = false
    end

    Follow.create!(follow_params)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create follow relationship: #{e.message}"
    raise
  end

  def generate_follow_ap_id(_target_actor, follow_id)
    "#{@actor.ap_id}#follows/#{follow_id}"
  end

  def send_follow_activity(follow)
    SendFollowJob.perform_later(follow)
  end
end
