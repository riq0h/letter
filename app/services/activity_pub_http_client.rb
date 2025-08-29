# frozen_string_literal: true

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
    return fetch_signed_object(uri, signing_actor || default_signing_actor, timeout) if signing_actor || requires_signature?(uri)

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
    # ActivitySenderのHTTP署名機能を流用
    activity_sender = ActivitySender.new

    # GETリクエスト用のダミーアクティビティを作成
    {
      'type' => 'Get',
      'id' => "#{signing_actor.ap_id}#get-#{SecureRandom.uuid}",
      'actor' => signing_actor.ap_id,
      'object' => uri
    }

    # ActivitySenderのHTTP署名生成機能を使用
    headers = activity_sender.send(:build_headers, uri, '', signing_actor)

    # GETリクエスト用にメソッドを変更
    headers.delete('Content-Type')
    headers['Accept'] = ACCEPT_HEADERS

    response = HTTParty.get(uri, headers: headers, timeout: timeout)
    return nil unless response.success?

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to fetch signed ActivityPub object #{uri}: #{e.message}"
    nil
  end
end
