# frozen_string_literal: true

require 'net/http'

class ActivityPubHttpClient
  include HTTParty

  USER_AGENT = 'letter/0.1'
  ACCEPT_HEADERS = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
  DEFAULT_TIMEOUT = 10

  def self.fetch_object(uri, timeout: DEFAULT_TIMEOUT)
    new.fetch_object(uri, timeout: timeout)
  end

  def fetch_object(uri, timeout: DEFAULT_TIMEOUT, signing_actor: nil)
    # HTTP署名が明示的に指定されている場合は署名付きで送信
    return fetch_with_signature(uri, signing_actor, timeout) if signing_actor

    domain = extract_domain(uri)

    # 学習済みの署名必須ドメインの場合は最初から署名付きで送信
    return fetch_with_learned_signature(uri, domain, timeout) if signature_required_for_domain?(domain)

    # 通常のリクエストを試行
    response = attempt_unsigned_request(uri, timeout)

    # 署名が必要な場合は学習して再試行
    return handle_signature_requirement(uri, domain, response, timeout) if requires_signature?(response)

    return nil unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "❌ Invalid JSON in ActivityPub object #{uri}: #{e.message}"
    nil
  rescue Net::TimeoutError => e
    Rails.logger.error "❌ Timeout fetching ActivityPub object #{uri}: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.error "❌ Failed to fetch ActivityPub object #{uri}: #{e.message}"
    nil
  end

  private

  # 学習済み署名でリクエスト
  def fetch_with_learned_signature(uri, domain, timeout)
    Rails.logger.info "🔐 Using learned HTTP signature for domain #{domain}"
    signing_actor = Actor.find_by(local: true)
    fetch_with_signature(uri, signing_actor, timeout) if signing_actor
  end

  # 署名なしリクエスト試行
  def attempt_unsigned_request(uri, timeout)
    HTTParty.get(
      uri,
      headers: {
        'Accept' => ACCEPT_HEADERS,
        'User-Agent' => USER_AGENT,
        'Date' => Time.now.httpdate
      },
      timeout: timeout,
      follow_redirects: true
    )
  end

  # 署名要求のハンドリング
  def handle_signature_requirement(uri, domain, response, timeout)
    Rails.logger.info "🔐 #{response.code} received, learning signature requirement for #{domain}"
    learn_signature_requirement(domain)
    signing_actor = Actor.find_by(local: true)
    fetch_with_signature(uri, signing_actor, timeout) if signing_actor
  end

  # ドメイン抽出
  def extract_domain(uri)
    URI.parse(uri).host
  rescue URI::InvalidURIError
    nil
  end

  # 署名が必要なドメインかチェック
  def signature_required_for_domain?(domain)
    return false unless domain

    cache_key = "activitypub:signature_required:#{domain}"
    Rails.cache.read(cache_key) == true
  end

  # 署名要求を学習してキャッシュに保存
  def learn_signature_requirement(domain)
    return unless domain

    cache_key = "activitypub:signature_required:#{domain}"
    Rails.cache.write(cache_key, true, expires_in: 30.days)
    Rails.logger.info "📚 Learned signature requirement for domain: #{domain}"
  end

  # レスポンスがHTTP署名を要求しているかチェック
  def requires_signature?(response)
    # 401 Unauthorized または 403 Forbidden
    return true if [401, 403].include?(response.code)

    # WWW-Authenticate ヘッダーで署名を要求している場合
    auth_header = response.headers['WWW-Authenticate']
    return true if auth_header&.include?('Signature')

    # その他の署名要求指示
    false
  end

  def fetch_with_signature(uri, signing_actor, timeout)
    date = Time.now.httpdate
    uri_obj = URI(uri)

    headers = {
      'Accept' => ACCEPT_HEADERS,
      'User-Agent' => USER_AGENT,
      'Date' => date,
      'Host' => uri_obj.host
    }

    # GETリクエスト用のHTTP署名を生成（content-typeを除外）
    signature = generate_get_signature(uri, date, signing_actor)
    headers['Signature'] = signature if signature

    response = HTTParty.get(uri, headers: headers, timeout: timeout)
    return nil unless response.success?

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to fetch signed ActivityPub object #{uri}: #{e.message}"
    nil
  end

  def generate_get_signature(url, date, actor)
    uri = URI(url)

    # GETリクエスト用の署名対象文字列（content-typeを除外）
    signing_string = [
      "(request-target): get #{uri.path}",
      "host: #{uri.host}",
      "date: #{date}",
      "accept: #{ACCEPT_HEADERS}"
    ].join("\n")

    private_key = actor.private_key_object
    return nil unless private_key

    signature = private_key.sign(OpenSSL::Digest.new('SHA256'), signing_string)
    encoded_signature = Base64.strict_encode64(signature)

    signature_params = [
      "keyId=\"#{actor.ap_id}#main-key\"",
      'algorithm="rsa-sha256"',
      'headers="(request-target) host date accept"',
      "signature=\"#{encoded_signature}\""
    ]

    signature_params.join(',')
  rescue StandardError => e
    Rails.logger.error "❌ Failed to generate GET signature: #{e.message}"
    nil
  end
end
