# frozen_string_literal: true

require 'net/http'
require 'uri'

class ActivitySender
  include HTTParty
  include SsrfProtection

  def initialize
    @timeout = 60
  end

  def send_activity(activity:, target_inbox:, signing_actor:)
    return { success: false, error: 'SSRF protection: blocked' } unless validate_url_for_ssrf!(target_inbox)

    body = activity.to_json
    headers = build_headers(target_inbox, body, signing_actor)

    Rails.logger.info "🔍 Sending #{activity['type']} activity to #{target_inbox} from #{signing_actor.ap_id}"
    Rails.logger.debug { "🔍 Activity body: #{body}" }
    Rails.logger.debug { "🔍 Request headers: #{headers.except('Signature')}" }

    response = perform_request(target_inbox, body, headers)

    handle_response(response, activity['type'], target_inbox)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error "⏰ Activity sending timeout: #{e.message}"
    { success: false, error: "Timeout: #{e.message}" }
  rescue Net::ProtocolError => e
    Rails.logger.error "🔌 Activity sending protocol error: #{e.message}"
    { success: false, error: "Protocol error: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error "💥 Activity sending error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def build_headers(target_inbox, body, signing_actor)
    date = Time.current.httpdate
    digest = generate_digest(body)
    {
      'Content-Type' => 'application/activity+json',
      'User-Agent' => InstanceConfig.user_agent(:activitypub),
      'Date' => date,
      'Host' => URI(target_inbox).host,
      'Digest' => digest,
      'Signature' => generate_http_signature(
        method: 'POST',
        url: target_inbox,
        date: date,
        digest: digest,
        actor: signing_actor
      )
    }
  end

  def perform_request(target_inbox, body, headers)
    # Net::HTTPを使用してヘッダーを正確に制御
    uri = URI(target_inbox)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 30
    http.read_timeout = @timeout

    request = Net::HTTP::Post.new(uri.path)
    request.body = body

    headers.each do |key, value|
      request[key] = value
    end

    Rails.logger.debug '🔍 Net::HTTP request headers:'
    request.each_header { |key, value| Rails.logger.debug "   #{key}: #{value}" }

    response = http.request(request)

    # HTTParty風のレスポンスオブジェクトを模倣
    MockResponse.new(response)
  end

  # HTTParty互換のレスポンスオブジェクト
  class MockResponse
    def initialize(net_http_response)
      @response = net_http_response
    end

    def success?
      @response.code.to_i.between?(200, 299)
    end

    def code
      @response.code.to_i
    end

    delegate :body, to: :@response

    def headers
      @response.to_hash
    end

    delegate :message, to: :@response
  end

  def handle_response(response, activity_type, target_inbox = nil)
    if response.success?
      { success: true, code: response.code }
    elsif response.code == 410
      handle_gone_response(target_inbox, response, activity_type)
    else
      error_msg = "#{response.code} - #{response.body.to_s[0..200]}"
      Rails.logger.error "❌ #{activity_type} sending failed: #{error_msg}"
      Rails.logger.error "🔍 Target inbox: #{target_inbox}"
      Rails.logger.error "🔍 Response headers: #{response.headers}"
      { success: false, error: error_msg, code: response.code }
    end
  end

  # HTTP Signature生成
  def generate_http_signature(method:, url:, date:, digest:, actor:)
    uri = URI(url)

    # request-targetの構築（パス + クエリパラメータ）
    request_target_path = uri.path
    request_target_path += "?#{uri.query}" if uri.query

    # 署名対象文字列構築
    signing_string = [
      "(request-target): #{method.downcase} #{request_target_path}",
      "host: #{uri.host}",
      "date: #{date}",
      "digest: #{digest}",
      'content-type: application/activity+json'
    ].join("\n")

    Rails.logger.debug { "🔍 HTTP Signature signing string:\n#{signing_string}" }

    # 秘密鍵で署名（ActorKeyManagerを使用）
    private_key = actor.private_key_object
    unless private_key
      Rails.logger.error "❌ No private key found for actor #{actor.ap_id}"
      return nil
    end

    signature = private_key.sign(OpenSSL::Digest.new('SHA256'), signing_string)
    encoded_signature = Base64.strict_encode64(signature)

    # Signature headerフォーマット（スペースを含めない形式）
    signature_params = [
      "keyId=\"#{actor.ap_id}#main-key\"",
      'algorithm="rsa-sha256"',
      'headers="(request-target) host date digest content-type"',
      "signature=\"#{encoded_signature}\""
    ]

    signature_header = signature_params.join(',')
    Rails.logger.debug { "🔍 HTTP Signature header: #{signature_header}" }
    Rails.logger.debug { "🔍 HTTP Signature header length: #{signature_header.length}" }

    signature_header
  end

  # SHA256ダイジェスト生成
  def generate_digest(body)
    digest = Digest::SHA256.digest(body)
    "SHA-256=#{Base64.strict_encode64(digest)}"
  end

  # 410 Gone応答の処理
  def handle_gone_response(target_inbox, response, _activity_type)
    return { success: false, error: 'No target inbox provided', code: 410 } unless target_inbox

    begin
      domain = URI(target_inbox).host
      error_msg = "410 Gone - #{response.body.to_s[0..200]}"

      Rails.logger.warn "🚫 Server gone (410): #{domain} - marking as unavailable"

      # UnavailableServerに記録
      unavailable_server = UnavailableServer.record_gone_response(domain, error_msg)

      # フォロー関係のクリーンアップを非同期で実行
      CleanupUnavailableServerJob.perform_later(unavailable_server.id)

      { success: false, error: error_msg, code: 410, domain_marked_unavailable: true }
    rescue URI::InvalidURIError => e
      Rails.logger.error "🔗 Invalid inbox URI: #{target_inbox} - #{e.message}"
      { success: false, error: "Invalid inbox URI: #{e.message}", code: 410 }
    rescue StandardError => e
      Rails.logger.error "💥 Error handling 410 response: #{e.message}"
      { success: false, error: "Error handling 410: #{e.message}", code: 410 }
    end
  end
end
