# frozen_string_literal: true

class FollowService
  include ActivityPubHelper

  def initialize(actor)
    @actor = actor
  end

  # Follow a remote or local actor
  def follow!(target_actor_uri_or_actor, options = {})
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return nil unless target_actor

    # Check if already following
    existing_follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return existing_follow if existing_follow

    # Create the follow relationship
    follow = create_follow_relationship(target_actor, options)

    # Send ActivityPub follow activity if target is remote
    send_follow_activity(follow) if target_actor.domain.present?

    follow
  end

  # Unfollow an actor
  def unfollow!(target_actor_uri_or_actor)
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return false unless target_actor

    follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return false unless follow

    follow.unfollow!
    true
  end

  private

  def resolve_target_actor(target_actor_uri_or_actor)
    case target_actor_uri_or_actor
    when Actor
      target_actor_uri_or_actor
    when String
      if target_actor_uri_or_actor.match?(/^https?:\/\//)
        # ActivityPub URI
        fetch_remote_actor_by_uri(target_actor_uri_or_actor)
      else
        # Handle @username@domain format
        username, domain = parse_acct(target_actor_uri_or_actor)
        find_or_fetch_actor(username, domain)
      end
    end
  end

  def parse_acct(acct)
    # Handle formats: @username@domain or username@domain
    clean_acct = acct.gsub(/^@/, '')
    parts = clean_acct.split('@')

    if parts.length == 2
      [parts[0], parts[1]]
    else
      [clean_acct, nil] # Local user
    end
  end

  def find_or_fetch_actor(username, domain)
    if domain.nil?
      # Local actor
      Actor.find_by(username: username, local: true)
    else
      # Remote actor - find existing or fetch from remote
      existing_actor = Actor.find_by(username: username, domain: domain)
      return existing_actor if existing_actor

      # Fetch from remote using WebFinger
      fetch_remote_actor(username, domain)
    end
  end

  def fetch_remote_actor(username, domain)
    webfinger_uri = "acct:#{username}@#{domain}"
    webfinger_service = WebFingerService.new

    actor_data = webfinger_service.fetch_actor_data(webfinger_uri)
    return nil unless actor_data

    create_remote_actor_from_data(actor_data)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch remote actor #{username}@#{domain}: #{e.message}"
    nil
  end

  def fetch_remote_actor_by_uri(uri)
    # Fetch actor data directly from ActivityPub URI
    response = fetch_activitypub_object(uri)
    return nil unless response

    create_remote_actor_from_data(response)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch actor from URI #{uri}: #{e.message}"
    nil
  end

  def create_remote_actor_from_data(actor_data)
    Actor.create!(build_actor_attributes(actor_data))
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create remote actor: #{e.message}"
    nil
  end

  def build_actor_attributes(actor_data)
    {
      **basic_actor_attributes(actor_data),
      **activitypub_urls(actor_data),
      **actor_metadata(actor_data)
    }
  end

  def basic_actor_attributes(actor_data)
    {
      username: actor_data['preferredUsername'],
      domain: URI.parse(actor_data['id']).host,
      display_name: actor_data['name'],
      summary: actor_data['summary'],
      ap_id: actor_data['id'],
      local: false
    }
  end

  def activitypub_urls(actor_data)
    {
      inbox_url: actor_data['inbox'],
      outbox_url: actor_data['outbox'],
      followers_url: actor_data['followers'],
      following_url: actor_data['following'],
      public_key: actor_data.dig('publicKey', 'publicKeyPem')
    }
  end

  def actor_metadata(actor_data)
    {
      avatar_url: actor_data.dig('icon', 'url'),
      header_url: actor_data.dig('image', 'url'),
      actor_type: actor_data['type'] || 'Person',
      discoverable: actor_data['discoverable'],
      manually_approves_followers: actor_data['manuallyApprovesFollowers'],
      raw_data: actor_data.to_json
    }
  end

  def create_follow_relationship(target_actor, _options = {})
    follow_params = {
      actor: @actor,
      target_actor: target_actor,
      ap_id: generate_follow_ap_id(target_actor),
      follow_activity_ap_id: generate_follow_ap_id(target_actor)
    }

    # For local follows, auto-accept unless target requires approval
    if target_actor.local?
      follow_params[:accepted] = !target_actor.manually_approves_followers
      follow_params[:accepted_at] = Time.current if follow_params[:accepted]
    else
      # Remote follows start as pending
      follow_params[:accepted] = false
    end

    Follow.create!(follow_params)
  end

  def generate_follow_ap_id(target_actor)
    "#{@actor.ap_id}#follows/#{target_actor.username}@#{target_actor.domain || 'local'}/#{SecureRandom.uuid}"
  end

  def send_follow_activity(follow)
    Rails.logger.info "📤 Sending Follow activity for #{@actor.username} -> #{follow.target_actor.username}@#{follow.target_actor.domain}"
    SendFollowJob.perform_later(follow)
  end
end
