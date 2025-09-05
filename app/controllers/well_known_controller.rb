# frozen_string_literal: true

class WellKnownController < ApplicationController
  include UrlBuildable
  skip_before_action :verify_authenticity_token

  # GET /.well-known/webfinger
  # RFC 7033 WebFinger実装
  def webfinger
    resource = params[:resource]

    return render_webfinger_error('Missing resource parameter') if resource.blank?

    actor = find_actor_by_resource(resource)

    return render_webfinger_error('Actor not found') unless actor

    render json: build_webfinger_response(actor),
           content_type: 'application/jrd+json; charset=utf-8'
  end

  # GET /.well-known/host-meta
  # RFC 6415 Host Metadata実装
  def host_meta
    render xml: build_host_meta_response,
           content_type: 'application/xrd+xml; charset=utf-8'
  end

  # GET /.well-known/nodeinfo
  # NodeInfo Discovery実装
  def nodeinfo
    render json: build_nodeinfo_discovery_response,
           content_type: 'application/json; charset=utf-8'
  end

  private

  def find_actor_by_resource(resource)
    case resource
    when /^acct:/
      find_actor_by_acct(resource)
    when /^http/
      find_actor_by_url(resource)
    end
  end

  def find_actor_by_acct(resource)
    username, domain = parse_acct_resource(resource)
    return nil unless domain_matches?(domain)

    Actor.find_by(username: username, local: true)
  end

  def parse_acct_resource(resource)
    identifier = AccountIdentifier.new_from_acct_uri(resource)
    identifier ? [identifier.username, identifier.domain] : []
  end

  def find_actor_by_url(resource)
    uri = URI.parse(resource)
    return nil unless host_matches?(uri.host)

    extract_actor_from_path(uri.path) || Actor.find_by(ap_id: resource, local: true)
  end

  def domain_matches?(domain)
    request_domain = request&.host
    config_domain = Rails.application.config.activitypub.domain
    domain == request_domain || domain == config_domain
  end

  def host_matches?(host)
    request_host = request&.host
    config_host = Rails.application.config.activitypub.domain.split(':').first
    host == request_host || host == config_host
  end

  def extract_actor_from_path(path)
    return nil unless path =~ /^\/@(\w+)$/

    username = ::Regexp.last_match(1)
    Actor.find_by(username: username, local: true)
  end

  def build_webfinger_response(actor)
    domain = Rails.application.config.activitypub.domain
    actor_url = "#{base_url}/users/#{actor.username}"
    profile_url = "#{base_url}/users/#{actor.username}"
    subject = "acct:#{actor.username}@#{domain}"

    # ログでドメイン設定を確認
    Rails.logger.info "WebFinger: domain=#{domain}, base_url=#{base_url}"

    {
      subject: subject,
      aliases: [
        actor_url,
        profile_url
      ].compact,
      properties: {
        'http://schema.org/name' => actor.display_name || actor.username,
        'http://ostatus.org/schema/1.0/domain' => domain
      },
      links: [
        {
          rel: 'self',
          type: 'application/activity+json',
          href: actor_url
        },
        {
          rel: 'http://webfinger.net/rel/profile-page',
          type: 'text/html',
          href: profile_url
        },
        {
          rel: 'http://ostatus.org/schema/1.0/subscribe',
          template: "#{base_url}/authorize_interaction?uri={uri}"
        },
        {
          rel: 'http://webfinger.net/rel/avatar',
          type: 'image/png',
          href: actor.avatar_url
        }.compact_blank
      ].compact
    }
  end

  def build_host_meta_response
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <XRD xmlns="http://docs.oasis-open.org/ns/xri/xrd-1.0">
        <Link rel="lrdd" template="#{base_url}/.well-known/webfinger?resource={uri}"/>
      </XRD>
    XML
  end

  def build_nodeinfo_discovery_response
    {
      links: [
        {
          rel: 'http://nodeinfo.diaspora.software/ns/schema/2.1',
          href: "#{base_url}/nodeinfo/2.1"
        }
      ]
    }
  end

  def base_url
    @base_url ||= build_url_from_config
  end

  def render_webfinger_error(message)
    render json: { error: message },
           status: :not_found,
           content_type: 'application/jrd+json; charset=utf-8'
  end
end
