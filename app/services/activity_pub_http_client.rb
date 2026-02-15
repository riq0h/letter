# frozen_string_literal: true

require 'net/http'

class ActivityPubHttpClient
  include HTTParty
  include SsrfProtection
  include ActivityPubUtilityHelpers

  USER_AGENT = InstanceConfig.user_agent(:activitypub)
  ACCEPT_HEADERS = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
  DEFAULT_TIMEOUT = 10

  def self.fetch_object(uri, timeout: DEFAULT_TIMEOUT)
    new.fetch_object(uri, timeout: timeout)
  end

  def fetch_object(uri, timeout: DEFAULT_TIMEOUT, signing_actor: nil)
    return nil unless validate_url_for_ssrf!(uri)
    # HTTP署名が明示的に指定されている場合は署名付きで送信
    return fetch_with_signature(uri, signing_actor, timeout) if signing_actor

    domain = extract_domain_from_uri(uri)

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
  def attempt_unsigned_request(uri, timeout, redirect_depth: 0)
    return nil if redirect_depth >= MAX_REDIRECT_DEPTH

    response = HTTParty.get(
      uri,
      headers: {
        'Accept' => ACCEPT_HEADERS,
        'User-Agent' => USER_AGENT,
        'Date' => Time.current.httpdate
      },
      timeout: timeout,
      follow_redirects: false
    )

    if [301, 302, 307, 308].include?(response.code) && response.headers['location']
      redirect_uri = response.headers['location']
      return nil unless validate_url_for_ssrf!(redirect_uri)

      attempt_unsigned_request(redirect_uri, timeout, redirect_depth: redirect_depth + 1)
    else
      response
    end
  end

  # 署名要求のハンドリング
  def handle_signature_requirement(uri, domain, response, timeout)
    Rails.logger.info "🔐 #{response.code} received, learning signature requirement for #{domain}"
    learn_signature_requirement(domain)
    signing_actor = Actor.find_by(local: true)
    fetch_with_signature(uri, signing_actor, timeout) if signing_actor
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
    # 認証・認可エラー（401, 403）のみ署名要求として扱う
    # 404はリソース不在、500はサーバエラーであり署名とは無関係
    return true if [401, 403].include?(response.code.to_i)

    # WWW-Authenticate ヘッダーで署名を要求している場合
    auth_header = response.headers['WWW-Authenticate']
    return true if auth_header&.include?('Signature')

    # ActivityPubリクエストに対してHTMLが返された場合
    if response.success? && html_response_to_activitypub_request?(response)
      Rails.logger.info '🔍 HTML response detected for ActivityPub request - likely requires signature'
      return true
    end

    # その他の署名要求指示
    false
  end

  # ActivityPubリクエストに対してHTMLが返されたかチェック
  def html_response_to_activitypub_request?(response)
    content_type = response.headers['content-type']&.downcase || ''

    # HTMLコンテンツタイプ
    return true if content_type.include?('text/html')

    # Content-Typeが不明だがHTMLドキュメントの開始タグがある場合
    body = response.body&.strip
    return true if body&.start_with?('<!DOCTYPE', '<html', '<HTML')

    false
  end

  def fetch_with_signature(uri, signing_actor, timeout, redirect_depth: 0)
    return nil unless validate_url_for_ssrf!(uri)
    return nil if redirect_depth >= MAX_REDIRECT_DEPTH

    date = Time.current.httpdate
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

    # 署名付きリクエストではリダイレクトを無効にする（署名が無効になるため）
    response = HTTParty.get(uri, headers: headers, timeout: timeout, follow_redirects: false)

    # リダイレクトの場合はLocationヘッダーで再試行
    if [301, 302, 307, 308].include?(response.code) && response.headers['location']
      redirect_uri = response.headers['location']
      Rails.logger.info "🔀 Following redirect to: #{redirect_uri}"
      return fetch_with_signature(redirect_uri, signing_actor, timeout, redirect_depth: redirect_depth + 1)
    end

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
