# frozen_string_literal: true

require 'nokogiri'
require 'httparty'

class OgpFetcher
  include HTTParty

  default_timeout 10
  headers 'User-Agent' => 'Mozilla/5.0 (compatible; letter/0.1; +https://github.com/riq0h/letter)'

  def self.fetch(url)
    new.fetch(url)
  end

  def fetch(url)
    return nil unless valid_url?(url)

    response = self.class.get(url)
    return nil unless response.success?

    parse_ogp(response.body, url)
  rescue StandardError => e
    Rails.logger.warn "OGP fetch failed for #{url}: #{e.message}"
    nil
  end

  private

  def valid_url?(url)
    uri = URI.parse(url)
    %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def parse_ogp(html, url)
    doc = Nokogiri::HTML(html)

    {
      title: extract_title(doc),
      description: extract_description(doc),
      image: extract_image(doc, url),
      url: url,
      site_name: extract_site_name(doc),
      preview_type: extract_type(doc)
    }.compact
  end

  def extract_title(doc)
    doc.at_css('meta[property="og:title"]')&.[]('content') ||
      doc.at_css('meta[name="twitter:title"]')&.[]('content') ||
      doc.at_css('title')&.text&.strip
  end

  def extract_description(doc)
    description = doc.at_css('meta[property="og:description"]')&.[]('content') ||
                  doc.at_css('meta[name="twitter:description"]')&.[]('content') ||
                  doc.at_css('meta[name="description"]')&.[]('content')

    description&.truncate(500)
  end

  def extract_image(doc, base_url)
    image_url = doc.at_css('meta[property="og:image"]')&.[]('content') ||
                doc.at_css('meta[name="twitter:image"]')&.[]('content')

    return nil unless image_url

    # 相対URLを絶対URLに変換
    if image_url.start_with?('//')
      "https:#{image_url}"
    elsif image_url.start_with?('/')
      uri = URI.parse(base_url)
      "#{uri.scheme}://#{uri.host}#{image_url}"
    else
      image_url
    end
  end

  def extract_site_name(doc)
    doc.at_css('meta[property="og:site_name"]')&.[]('content')
  end

  def extract_type(doc)
    doc.at_css('meta[property="og:type"]')&.[]('content') || 'website'
  end
end
