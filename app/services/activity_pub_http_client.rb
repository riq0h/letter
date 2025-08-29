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
    # HTTP署名が必要な場合は署名付きで送信
    return fetch_with_signature(uri, signing_actor, timeout) if signing_actor

    response = HTTParty.get(
      uri,
      headers: {
        'Accept' => ACCEPT_HEADERS,
        'User-Agent' => USER_AGENT,
        'Date' => Time.now.httpdate
      },
      timeout: timeout,
      follow_redirects: true
    )

    # 401の場合は署名付きで再試行
    if response.code == 401
      Rails.logger.info "🔐 401 received, retrying with HTTP signature for #{uri}"
      signing_actor = Actor.find_by(local: true)
      return fetch_with_signature(uri, signing_actor, timeout) if signing_actor
    end

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
