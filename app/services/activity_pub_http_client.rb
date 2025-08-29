# frozen_string_literal: true

class ActivityPubHttpClient
  include HTTParty

  USER_AGENT = 'letter/0.1'
  ACCEPT_HEADERS = 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
  DEFAULT_TIMEOUT = 10

  def self.fetch_object(uri, timeout: DEFAULT_TIMEOUT)
    new.fetch_object(uri, timeout: timeout)
  end

  def fetch_object(uri, timeout: DEFAULT_TIMEOUT)
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
end
