# frozen_string_literal: true

class ActivitySender
  include HTTParty

  def initialize
    @timeout = 60
  end

  def send_activity(activity:, target_inbox:, signing_actor:)
    body = activity.to_json
    headers = build_headers(target_inbox, body, signing_actor)
    response = perform_request(target_inbox, body, headers)

    handle_response(response, activity['type'], target_inbox)
  rescue Net::TimeoutError => e
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
    {
      'Content-Type' => 'application/activity+json',
      'User-Agent' => 'letter/0.1 (ActivityPub)',
      'Date' => Time.now.httpdate,
      'Host' => URI(target_inbox).host,
      'Digest' => generate_digest(body),
      'Signature' => generate_http_signature(
        method: 'POST',
        url: target_inbox,
        body: body,
        actor: signing_actor
      )
    }
  end

  def perform_request(target_inbox, body, headers)
    HTTParty.post(
      target_inbox,
      body: body,
      headers: headers,
      timeout: @timeout,
      open_timeout: 30
    )
  end

  def handle_response(response, activity_type, target_inbox = nil)
    if response.success?
      { success: true, code: response.code }
    elsif response.code == 410
      handle_gone_response(target_inbox, response, activity_type)
    else
      error_msg = "#{response.code} - #{response.body.to_s[0..200]}"
      Rails.logger.error "❌ #{activity_type} sending failed: #{error_msg}"
      { success: false, error: error_msg, code: response.code }
    end
  end

  # HTTP Signature生成
  def generate_http_signature(method:, url:, body:, actor:)
    uri = URI(url)
    date = Time.now.httpdate
    digest = generate_digest(body)

    # 署名対象文字列構築
    signing_string = [
      "(request-target): #{method.downcase} #{uri.path}",
      "host: #{uri.host}",
      "date: #{date}",
      "digest: #{digest}",
      'content-type: application/activity+json'
    ].join("\n")

    # 秘密鍵で署名
    private_key = OpenSSL::PKey::RSA.new(actor.private_key)
    signature = private_key.sign(OpenSSL::Digest.new('SHA256'), signing_string)
    encoded_signature = Base64.strict_encode64(signature)

    # Signature headerフォーマット
    signature_params = [
      "keyId=\"#{actor.ap_id}#main-key\"",
      'algorithm="rsa-sha256"',
      'headers="(request-target) host date digest content-type"',
      "signature=\"#{encoded_signature}\""
    ]

    signature_params.join(',')
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
