# frozen_string_literal: true

class WebFingerService
  include HTTParty
  include ActivityPubHelper

  def fetch_actor_data(acct_uri)
    # acct: URIからユーザ名とドメインを抽出
    username, domain = parse_acct_uri(acct_uri)
    return nil unless username && domain

    # WebFingerデータを取得
    webfinger_data = fetch_webfinger(username, domain)
    return nil unless webfinger_data

    # ActivityPubアクターURIを抽出
    actor_uri = extract_actor_uri(webfinger_data)
    return nil unless actor_uri

    # ActivityPubアクターデータを取得
    fetch_activitypub_object(actor_uri)
  end

  private

  def parse_acct_uri(acct_uri)
    identifier = AccountIdentifier.parse_acct_uri(acct_uri)
    return nil unless identifier

    [identifier.username, identifier.domain]
  end

  def fetch_webfinger(username, domain)
    webfinger_url = "https://#{domain}/.well-known/webfinger"
    resource = AccountIdentifier.new(username, domain).to_webfinger_uri

    response = HTTParty.get(webfinger_url, {
                              query: { resource: resource },
                              headers: { 'Accept' => 'application/jrd+json' },
                              timeout: 10
                            })

    return nil unless response.success?

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error "WebFinger fetch failed for #{username}@#{domain}: #{e.message}"
    nil
  end

  def extract_actor_uri(webfinger_data)
    links = webfinger_data['links'] || []
    actor_link = links.find do |link|
      link['rel'] == 'self' &&
        link['type'] == 'application/activity+json'
    end

    actor_link&.dig('href')
  end
end
