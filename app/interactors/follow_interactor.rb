# frozen_string_literal: true

require 'net/http'
require 'stringio'

# アクターのフォロー・アンフォロー操作を担当するInteractor
# 複雑なビジネスロジックを単一の責任で管理
class FollowInteractor
  include ActivityPubHelper

  class Result
    attr_reader :success, :follow, :error

    def initialize(success:, follow: nil, error: nil)
      @success = success
      @follow = follow
      @error = error
      freeze
    end

    def success?
      success
    end

    def failure?
      !success
    end
  end

  def self.follow(actor, target_actor_uri_or_actor, options = {})
    new(actor).follow(target_actor_uri_or_actor, options)
  end

  def self.unfollow(actor, target_actor_uri_or_actor)
    new(actor).unfollow(target_actor_uri_or_actor)
  end

  def initialize(actor)
    @actor = actor
  end

  # リモートまたはローカルアクターをフォロー
  def follow(target_actor_uri_or_actor, options = {})
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return failure('Target actor not found') unless target_actor

    # 既にフォロー中か確認
    existing_follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return success(existing_follow) if existing_follow

    # フォロー関係を作成
    follow = create_follow_relationship(target_actor, options)
    return failure('Failed to create follow relationship') unless follow

    success(follow)
  rescue StandardError => e
    Rails.logger.error "Follow operation failed: #{e.message}"
    failure(e.message)
  end

  # アクターのフォローを解除
  def unfollow(target_actor_uri_or_actor)
    target_actor = resolve_target_actor(target_actor_uri_or_actor)
    return failure('Target actor not found') unless target_actor

    follow = Follow.find_by(actor: @actor, target_actor: target_actor)
    return failure('Follow relationship not found') unless follow

    follow.unfollow!
    success(follow)
  rescue StandardError => e
    Rails.logger.error "Unfollow operation failed: #{e.message}"
    failure(e.message)
  end

  private

  attr_reader :actor

  def success(follow)
    Result.new(success: true, follow: follow)
  end

  def failure(error)
    Result.new(success: false, error: error)
  end

  def resolve_target_actor(target_actor_uri_or_actor)
    case target_actor_uri_or_actor
    when Actor
      target_actor_uri_or_actor
    when String
      if target_actor_uri_or_actor.match?(/^https?:\/\//)
        # ActivityPub URI
        fetch_remote_actor_by_uri(target_actor_uri_or_actor)
      else
        # @username@domain形式を処理
        username, domain = parse_acct(target_actor_uri_or_actor)
        find_or_fetch_actor(username, domain)
      end
    end
  end

  def parse_acct(acct)
    identifier = AccountIdentifier.new_from_string(acct)
    return [nil, nil] unless identifier

    [identifier.username, identifier.domain]
  end

  def find_or_fetch_actor(username, domain)
    if domain.nil?
      # ローカルアクター
      Actor.find_by(username: username, local: true)
    else
      # リモートアクター - 既存を検索または新規取得
      existing_actor = Actor.find_by(username: username, domain: domain)
      return existing_actor if existing_actor

      # WebFingerを使用してリモートから取得
      fetch_remote_actor(username, domain)
    end
  end

  def fetch_remote_actor(username, domain)
    webfinger_uri = AccountIdentifier.new(username, domain).to_webfinger_uri
    webfinger_service = WebFingerService.new

    actor_data = webfinger_service.fetch_actor_data(webfinger_uri)
    return nil unless actor_data

    ActorCreationService.create_from_activitypub_data(actor_data)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch remote actor #{username}@#{domain}: #{e.message}"
    nil
  end

  def fetch_remote_actor_by_uri(uri)
    # ActivityPub URIから直接アクターデータを取得
    response = fetch_activitypub_object(uri)
    return nil unless response

    ActorCreationService.create_from_activitypub_data(response)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch actor from URI #{uri}: #{e.message}"
    nil
  end

  def create_follow_relationship(target_actor, _options = {})
    follow_id = Letter::Snowflake.generate
    follow_params = {
      id: follow_id,
      actor: @actor,
      target_actor: target_actor,
      ap_id: generate_follow_ap_id(target_actor, follow_id),
      follow_activity_ap_id: generate_follow_ap_id(target_actor, follow_id)
    }

    # ローカルフォローは手動承認が必要かどうかを確認
    if target_actor.local?
      # 手動承認が必要な場合は保留状態、そうでなければ自動承認
      follow_params[:accepted] = !target_actor.manually_approves_followers
      follow_params[:accepted_at] = Time.current if follow_params[:accepted]
    else
      # リモートフォローは保留状態で開始
      follow_params[:accepted] = false
    end

    Follow.create!(follow_params)
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create follow relationship: #{e.message}"
    nil
  end

  def generate_follow_ap_id(_target_actor, follow_id)
    "#{@actor.ap_id}#follows/#{follow_id}"
  end
end
