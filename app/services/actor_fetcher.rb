# frozen_string_literal: true

require 'net/http'
require_relative 'concerns/actor_attachment_processing'
require_relative 'concerns/featured_collection_fetching'
require_relative 'concerns/emoji_tag_processing'

class ActorFetcher
  include ActorAttachmentProcessing
  include FeaturedCollectionFetching
  include EmojiTagProcessing
  include SsrfProtection

  def initialize
    @timeout = 15
  end

  def fetch_and_create(actor_uri)
    return nil unless validate_url_for_ssrf!(actor_uri)

    # 重複チェック
    existing_actor = Actor.find_by(ap_id: actor_uri)
    return existing_actor if existing_actor

    # アクターデータ取得
    actor_data = fetch_actor_data(actor_uri)

    # アクター作成
    create_actor_from_data(actor_uri, actor_data)
  rescue StandardError => e
    Rails.logger.error "❌ Actor fetch failed: #{e.message}"
    nil
  end

  def fetch_actor_data(actor_uri)
    actor_data = ActivityPubHttpClient.fetch_object(actor_uri)
    raise ActivityPub::ActorFetchError, "Failed to fetch actor: #{actor_uri}" unless actor_data

    validate_actor_data(actor_data, actor_uri)

    actor_data
  end

  def create_actor_from_data(actor_uri, actor_data)
    uri = URI(actor_uri)
    username, domain = extract_actor_identity(actor_data, uri)
    public_key_pem = extract_public_key(actor_data)

    actor = Actor.create!(build_actor_attributes(actor_uri, actor_data, username, domain, public_key_pem))

    # emoji情報を処理
    process_emoji_tags(actor_data['tag'], domain: actor.domain)

    # Featured Collection（ピン留め投稿）を取得
    fetch_featured_collection_async(actor)

    actor
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "💾 Actor creation failed: #{e.message}"
    raise ActivityPub::ActorFetchError, "Database error: #{e.message}"
  end

  private

  def validate_actor_data(actor_data, expected_uri = nil)
    unless actor_data['type']&.match?(/Person|Service|Organization|Group/)
      raise ActivityPub::ActorFetchError,
            "Invalid actor type: #{actor_data['type']}"
    end

    required_fields = %w[id inbox outbox publicKey]
    missing_fields = required_fields.select { |field| actor_data[field].blank? }

    raise ActivityPub::ActorFetchError, "Missing required fields: #{missing_fields.join(', ')}" if missing_fields.any?

    # フェッチしたIDがリクエストしたURIと一致することを検証（なりすまし防止）
    return unless expected_uri && actor_data['id'] != expected_uri

    raise ActivityPub::ActorFetchError,
          "Actor ID mismatch: expected #{expected_uri}, got #{actor_data['id']}"
  end

  def extract_actor_identity(actor_data, uri)
    username = actor_data['preferredUsername'] ||
               actor_data['name']&.downcase&.gsub(/[^a-zA-Z0-9_]/, '') ||
               File.basename(uri.path)
    domain = uri.host
    [username, domain]
  end

  def extract_public_key(actor_data)
    public_key_pem = actor_data.dig('publicKey', 'publicKeyPem')
    raise ActivityPub::ActorFetchError, 'Missing public key in actor data' unless public_key_pem

    public_key_pem
  end

  def build_actor_attributes(actor_uri, actor_data, username, domain, public_key_pem)
    {
      ap_id: actor_uri,
      username: username,
      domain: domain,
      display_name: decode_actor_display_name(actor_data),
      note: decode_actor_note(actor_data),
      actor_type: actor_data['type'],
      inbox_url: actor_data['inbox'],
      outbox_url: actor_data['outbox'],
      followers_url: actor_data['followers'],
      following_url: actor_data['following'],
      featured_url: extract_featured_url(actor_data['featured']),
      public_key: public_key_pem,
      raw_data: actor_data.to_json,
      fields: extract_fields_from_attachments(actor_data).to_json,
      local: false,
      discoverable: actor_data['discoverable'] != false,
      bot: actor_data['bot'] == true,
      manually_approves_followers: actor_data['manuallyApprovesFollowers'] == true
    }
  end
end
