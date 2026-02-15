# frozen_string_literal: true

module ActivityPubUtilityHelpers
  extend ActiveSupport::Concern

  private

  def find_target_object(object_ap_id)
    target_object = ActivityPubObject.find_by(ap_id: object_ap_id)

    unless target_object
      Rails.logger.info "🔍 Target object not found locally, fetching: #{object_ap_id}"
      target_object = fetch_remote_object(object_ap_id)
    end

    Rails.logger.warn "⚠️ Target object not found for activity: #{object_ap_id}" unless target_object

    target_object
  end

  def fetch_remote_object(ap_id)
    resolver = Search::RemoteResolverService.new
    resolver.resolve_remote_status(ap_id)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch remote object #{ap_id}: #{e.message}"
    nil
  end

  def strip_html_tags(html_content)
    return '' if html_content.blank?

    ActionController::Base.helpers.strip_tags(html_content)
  end

  def parse_published_date(published_str)
    return Time.current unless published_str

    Time.zone.parse(published_str)
  rescue StandardError
    Time.current
  end

  def extract_activity_object_id(object_data)
    object_data.is_a?(Hash) ? object_data['id'] : object_data
  end

  def extract_domain_from_uri(uri)
    return nil unless uri

    URI.parse(uri).host
  rescue URI::InvalidURIError
    nil
  end
end
