# frozen_string_literal: true

require_relative 'concerns/actor_attachment_processing'
require_relative 'concerns/featured_collection_fetching'

class HttpSignatureVerifier
  include ActorAttachmentProcessing
  include FeaturedCollectionFetching

  attr_reader :method, :path, :headers, :body

  def initialize(method:, path:, headers:, body:)
    @method = method.upcase
    @path = path
    @headers = headers
    @body = body
  end

  def verify!(actor_uri)
    signature_params = parse_signature_header
    return false unless signature_params
    return false unless validate_date_header

    # 初回署名検証試行
    public_key = fetch_actor_public_key(actor_uri)
    return false unless public_key

    signing_string = build_signing_string(signature_params['headers'])

    result = verify_signature(
      signature: signature_params['signature'],
      signing_string: signing_string,
      public_key: public_key
    )

    # 失敗時のフォールバック: アクターキーリフレッシュ
    if !result && actor_key_needs_refresh?(actor_uri)
      public_key = fetch_actor_public_key(actor_uri, refresh: true)
      result = verify_signature(
        signature: signature_params['signature'],
        signing_string: signing_string,
        public_key: public_key
      )
    end

    result
  rescue StandardError => e
    Rails.logger.error "Signature verification failed: #{e.message}"
    false
  end

  def actor_key_needs_refresh?(actor_uri)
    actor = Actor.find_by(ap_id: actor_uri)
    return false unless actor

    # 24時間以上前に作成されたアクターのキーをリフレッシュ対象とする
    actor.created_at < 24.hours.ago
  end

  def validate_date_header
    date_header = find_header_value('date')
    return true unless date_header

    begin
      request_time = Time.httpdate(date_header)
      time_diff = (Time.now.utc - request_time).abs
      time_diff <= 3600
    rescue ArgumentError
      false
    end
  end

  private

  # Signature header解析
  def parse_signature_header
    signature_header = headers['Signature']
    raise ActivityPub::SignatureError, 'Missing Signature header' unless signature_header

    params = {}

    # keyId="...",algorithm="...",headers="...",signature="..."
    signature_header.scan(/(\w+)="([^"]*)"/) do |key, value|
      params[key] = value
    end

    required_params = %w[keyId algorithm headers signature]
    missing = required_params - params.keys

    raise ActivityPub::SignatureError, "Missing signature parameters: #{missing.join(', ')}" if missing.any?

    params
  end

  # アクター公開鍵取得
  def fetch_actor_public_key(actor_uri, refresh: false)
    actor = Actor.find_by(ap_id: actor_uri)

    return parse_public_key(actor.public_key) if !refresh && actor&.public_key.present?

    response = fetch_actor_data(actor_uri)
    public_key_data = response.dig('publicKey', 'publicKeyPem')

    raise ActivityPub::SignatureError, 'No public key found in actor data' unless public_key_data

    if actor
      actor.update!(public_key: public_key_data)
    else
      create_remote_actor(actor_uri, response, public_key_data)
    end

    parse_public_key(public_key_data)
  end

  # アクターデータ取得
  def fetch_actor_data(actor_uri)
    uri = URI(actor_uri)
    http = configure_http_client(uri)
    request = build_actor_request(uri)
    response = http.request(request)

    validate_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise ActivityPub::SignatureError, "Invalid JSON in actor response: #{e.message}"
  rescue StandardError => e
    raise ActivityPub::SignatureError, "Network error fetching actor: #{e.message}"
  end

  # リモートアクター作成
  def create_remote_actor(actor_uri, actor_data, public_key_data)
    uri = URI(actor_uri)
    username = actor_data['preferredUsername'] || File.basename(uri.path)
    domain = uri.host

    actor = Actor.create!(
      ap_id: actor_uri,
      username: username,
      domain: domain,
      display_name: actor_data['name'],
      note: actor_data['summary'],
      inbox_url: actor_data['inbox'],
      outbox_url: actor_data['outbox'],
      followers_url: actor_data['followers'],
      following_url: actor_data['following'],
      featured_url: actor_data['featured'],
      public_key: public_key_data,
      raw_data: actor_data.to_json,
      fields: extract_fields_from_attachments(actor_data).to_json,
      local: false
    )

    # Featured Collection（ピン留め投稿）を取得
    fetch_featured_collection_async(actor)

    actor
  end

  # 公開鍵解析
  def parse_public_key(public_key_pem)
    OpenSSL::PKey::RSA.new(public_key_pem)
  rescue StandardError => e
    raise ActivityPub::SignatureError, "Invalid public key format: #{e.message}"
  end

  # 署名文字列構築
  def build_signing_string(headers_list)
    header_names = headers_list.split
    signature_parts = build_signature_parts(header_names)
    signature_parts.join("\n")
  end

  def configure_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 10
    http.open_timeout = 5
    http
  end

  def build_actor_request(uri)
    request = Net::HTTP::Get.new(uri.path)
    request['Accept'] = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
    request['User-Agent'] = InstanceConfig.user_agent(:activitypub)
    request
  end

  def validate_response(response)
    raise ActivityPub::SignatureError, "Failed to fetch actor: HTTP #{response.code}" unless response.code == '200'
  end

  def build_signature_parts(header_names)
    header_names.map do |header_name|
      part = build_signature_part(header_name)
      part
    end
  end

  def build_signature_part(header_name)
    normalized_name = header_name.downcase
    if normalized_name == '(request-target)'
      build_request_target_header
    elsif standard_headers.key?(normalized_name)
      build_standard_header(normalized_name)
    else
      build_custom_header(header_name)
    end
  end

  def standard_headers
    {
      'host' => find_header_value('host'),
      'date' => find_header_value('date'),
      'digest' => find_header_value('digest'),
      'content-type' => find_header_value('content-type'),
      'content-length' => find_header_value('content-length')
    }
  end

  def find_header_value(header_name)
    # Railsのheadersオブジェクトは文字列キーではなく、別の形式の可能性
    headers[header_name] ||
      headers[header_name.downcase] ||
      headers[header_name.upcase] ||
      headers[header_name.titleize] ||
      headers.find { |k, _v| k.to_s.downcase == header_name.downcase }&.last
  end

  def build_request_target_header
    "(request-target): #{method.downcase} #{path}"
  end

  def build_standard_header(header_name)
    value = standard_headers[header_name]
    # Mastodon標準: ヘッダー値の前後の空白を除去し、内部の連続空白を単一空白に正規化
    normalized_value = value.to_s.strip.gsub(/\s+/, ' ')
    "#{header_name}: #{normalized_value}"
  end

  def build_custom_header(header_name)
    value = find_header_value(header_name)
    # Mastodon標準: ヘッダー値の正規化
    normalized_value = value.to_s.strip.gsub(/\s+/, ' ')
    "#{header_name.downcase}: #{normalized_value}"
  end

  # 署名検証
  def verify_signature(signature:, signing_string:, public_key:)
    # Base64デコード
    decoded_signature = Base64.decode64(signature.gsub(/\s+/, ''))

    # 署名文字列を正規化
    normalized_signing_string = signing_string.encode('UTF-8', invalid: :replace, undef: :replace)

    # RSA-SHA256で検証
    result = public_key.verify('SHA256', decoded_signature, normalized_signing_string)

    # 253バイト署名の場合はパディングして再試行
    unless result
      key_size_bytes = public_key.n.num_bytes
      if decoded_signature.length < key_size_bytes
        padding_needed = key_size_bytes - decoded_signature.length
        adjusted_signature = ("\x00" * padding_needed) + decoded_signature
        result = public_key.verify('SHA256', adjusted_signature, normalized_signing_string)
      end
    end

    result
  rescue StandardError
    false
  end
end
