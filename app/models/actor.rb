# frozen_string_literal: true

class Actor < ApplicationRecord
  include UrlBuildable

  has_secure_password validations: false

  attribute :settings, :json, default: -> { {} }

  # アソシエーション
  has_many :objects, dependent: :destroy, class_name: 'ActivityPubObject'
  has_many :activities, dependent: :destroy
  has_many :media_attachments, dependent: :destroy
  has_many :favourites, dependent: :destroy
  has_many :reblogs, dependent: :destroy
  has_many :mentions, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :featured_tags, dependent: :destroy
  has_many :followed_tags, dependent: :destroy
  has_many :quote_posts, dependent: :destroy
  has_many :markers, dependent: :destroy
  has_many :scheduled_statuses, dependent: :destroy
  has_many :poll_votes, dependent: :destroy
  has_many :pinned_statuses, dependent: :destroy
  has_many :lists, dependent: :destroy
  has_many :list_memberships, dependent: :destroy
  has_many :filters, dependent: :destroy
  has_many :web_push_subscriptions, dependent: :destroy
  has_many :notifications, dependent: :destroy, foreign_key: :account_id, inverse_of: :account
  has_many :sent_notifications, dependent: :destroy, foreign_key: :from_account_id, class_name: 'Notification', inverse_of: :from_account

  # Active Storage統合
  has_one_attached :avatar
  has_one_attached :header

  # カスタムアップロードメソッド（フォルダ構造対応）
  def attach_avatar_with_folder(io:, filename:, content_type:)
    ActorImageProcessor.new(self).attach_avatar_with_folder(io: io, filename: filename, content_type: content_type)
  end

  # フォロー関係
  has_many :follows, dependent: :destroy
  has_many :followed_actors, -> { where(follows: { accepted: true }) }, through: :follows, source: :target_actor
  has_many :following, -> { where(follows: { accepted: true }) }, through: :follows, source: :target_actor # followed_actorsのエイリアス
  has_many :reverse_follows, class_name: 'Follow', foreign_key: 'target_actor_id', dependent: :destroy, inverse_of: :target_actor
  has_many :followers, -> { where(follows: { accepted: true }) }, through: :reverse_follows, source: :actor

  # ブロック・ミュート関係
  has_many :blocks, dependent: :destroy
  has_many :blocked_actors, through: :blocks, source: :target_actor
  has_many :blocked_by, class_name: 'Block', foreign_key: :target_actor_id, dependent: :destroy, inverse_of: :target_actor
  has_many :blocking_actors, through: :blocked_by, source: :actor

  has_many :mutes, dependent: :destroy
  has_many :muted_actors, through: :mutes, source: :target_actor
  has_many :muted_by, class_name: 'Mute', foreign_key: :target_actor_id, dependent: :destroy, inverse_of: :target_actor
  has_many :muting_actors, through: :muted_by, source: :actor

  # ドメインブロック
  has_many :domain_blocks, dependent: :destroy

  # アカウントメモ
  has_many :account_notes, dependent: :destroy
  has_many :account_notes_received, class_name: 'AccountNote', foreign_key: :target_actor_id, dependent: :destroy, inverse_of: :target_actor

  # 会話
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants

  # OAuth 2.0関連
  has_many :access_grants,
           class_name: 'Doorkeeper::AccessGrant',
           foreign_key: :resource_owner_id,
           dependent: :delete_all,
           inverse_of: :resource_owner

  has_many :access_tokens,
           class_name: 'Doorkeeper::AccessToken',
           foreign_key: :resource_owner_id,
           dependent: :delete_all,
           inverse_of: :resource_owner

  # バリデーション
  validates :username, presence: true, format: { with: /\A[a-zA-Z0-9_.-]+\z/ }
  validates :ap_id, presence: true, uniqueness: true, if: -> { !local? || !new_record? }
  validates :inbox_url, presence: true, if: -> { !local? || !new_record? }
  validates :outbox_url, presence: true, if: -> { !local? || !new_record? }
  validates :public_key, presence: true, if: -> { !local? || !new_record? }
  validates :password, length: { minimum: 6 }, if: -> { local? && password.present? }

  # ローカルアクター制限（SQLiteトリガーで制御）
  validate :local_actor_limit, if: -> { local? && !Rails.env.test? }

  # スコープ
  scope :local, -> { where(local: true) }
  scope :remote, -> { where(local: false) }
  scope :discoverable, -> { where(discoverable: true) }

  # コールバック
  before_validation :set_ap_urls, if: :local?, on: :create
  before_validation :generate_key_pair, if: :local?, on: :create
  before_create :set_admin_for_local_users, if: :local?
  after_update :distribute_profile_update, if: :should_distribute_profile_update?

  def setting(key)
    preferences[key.to_s]
  end

  def update_setting(key, value)
    current_settings = settings || {}
    update!(settings: current_settings.merge(key.to_s => value))
  end

  def default_settings
    {
      'posting:default:visibility' => 'public',
      'posting:default:sensitive' => false,
      'posting:default:language' => 'ja',
      'reading:expand:media' => 'default',
      'reading:expand:spoilers' => false,
      'reading:autoplay:gifs' => true,
      'web:advanced_layout' => false,
      'web:use_blurhash' => true,
      'web:use_pending_items' => false,
      'web:trends' => true,
      'notification_emails' => {
        'follow' => true,
        'reblog' => true,
        'favourite' => true,
        'mention' => true,
        'follow_request' => true,
        'digest' => true
      }
    }
  end

  def preferences
    default_settings.merge(settings || {})
  end

  # ActivityPub URL
  def followers_url
    return super if super.present?

    "#{ap_id}/followers" if local? && ap_id.present?
  end

  def following_url
    return super if super.present?

    "#{ap_id}/following" if local? && ap_id.present?
  end

  def featured_url
    return super if super.present?

    "#{ap_id}/collections/featured" if local? && ap_id.present?
  end

  # WebFinger識別子
  def webfinger_subject
    local_domain = Rails.application.config.activitypub.domain
    "acct:#{username}@#{domain || local_domain}"
  end

  # パブリック HTML URL (クライアント向けにはAPI形式)
  def public_url
    return nil unless local?

    base_url = Rails.application.config.activitypub.base_url
    "#{base_url}/users/#{username}"
  end

  # 表示メソッド
  def display_name_or_username
    display_name.presence || username
  end

  def full_username
    local? ? username : "#{username}@#{domain}"
  end

  # キー管理
  def public_key_object
    ActorKeyManager.new(self).public_key_object
  end

  def private_key_object
    ActorKeyManager.new(self).private_key_object
  end

  def public_key_id
    ActorKeyManager.new(self).public_key_id
  end

  # アクティビティ生成
  def generate_follow_activity(target_actor, follow_id)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'Follow',
      'id' => "#{ap_id}#follows/#{follow_id}",
      'actor' => ap_id,
      'object' => target_actor.ap_id
    }
  end

  def generate_accept_activity(follow)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'Accept',
      'id' => "#{ap_id}#accepts/follows/#{follow.id}",
      'actor' => ap_id,
      'object' => {
        'type' => 'Follow',
        'id' => follow.follow_activity_ap_id,
        'actor' => follow.actor.ap_id,
        'object' => ap_id
      }
    }
  end

  # ActivityPub JSON-LD representation
  def to_activitypub(request = nil)
    ActorSerializer.new(self).to_activitypub(request)
  end

  # フォロー・フォロワー数の更新
  def update_following_count!
    count = follows.accepted.count
    update_column(:following_count, count)
  end

  def update_followers_count!
    count = reverse_follows.accepted.count
    update_column(:followers_count, count)
  end

  # 投稿数の更新
  def update_posts_count!
    count = objects.where(object_type: 'Note', local: true).count
    update_column(:posts_count, count)
  end

  # ブロック・ミュートヘルパーメソッド
  def blocking?(actor)
    return false unless actor

    blocks.exists?(target_actor: actor)
  end

  def blocked_by?(actor)
    return false unless actor

    blocked_by.exists?(actor: actor)
  end

  def muting?(actor)
    return false unless actor

    mutes.exists?(target_actor: actor)
  end

  def muted_by?(actor)
    return false unless actor

    muted_by.exists?(actor: actor)
  end

  def domain_blocking?(domain)
    return false unless domain

    domain_blocks.exists?(domain: domain)
  end

  def domain_blocked_by?(actor_domain)
    return false unless actor_domain && domain.present?

    DomainBlock.exists?(domain: domain)
  end

  # Mastodon互換のacctメソッド
  def acct
    local? ? username : "#{username}@#{domain}"
  end

  # Active Storage画像URLの取得
  def avatar_url(skip_accessibility_check: false)
    ActorImageProcessor.new(self).avatar_url(skip_accessibility_check: skip_accessibility_check)
  end

  def header_url
    ActorImageProcessor.new(self).header_url
  end

  def extract_remote_image_url(field_name)
    return nil if raw_data.blank?

    begin
      actor_data = parse_actor_data
      return nil unless actor_data

      extract_image_url(actor_data[field_name])
    rescue JSON::ParserError => e
      log_parse_error(e)
      nil
    rescue StandardError => e
      log_extraction_error(field_name, e)
      nil
    end
  end

  # Shared inbox URLを取得（ActivityPub federation用）
  def shared_inbox_url
    return nil if raw_data.blank?

    begin
      actor_data = parse_actor_data
      return nil unless actor_data

      actor_data.dig('endpoints', 'sharedInbox')
    rescue JSON::ParserError => e
      Rails.logger.warn "Failed to parse raw_data for shared inbox: #{e.message}"
      nil
    rescue StandardError => e
      Rails.logger.warn "Failed to extract shared inbox URL: #{e.message}"
      nil
    end
  end

  private

  def parse_actor_data
    case raw_data
    when String
      parse_raw_data_string(raw_data)
    when Hash
      raw_data
    end
  end

  def log_parse_error(error)
    Rails.logger.warn "Failed to parse raw_data for #{username}@#{domain}: #{error.message}"
  end

  def log_extraction_error(field_name, error)
    Rails.logger.warn "Failed to extract #{field_name} URL for #{username}@#{domain}: #{error.message}"
  end

  # raw_data文字列をパース（JSON形式またはRuby Hash形式に対応）
  def parse_raw_data_string(data_string)
    # まずJSONとしてパースを試行
    begin
      return JSON.parse(data_string)
    rescue JSON::ParserError
      # JSONでない場合は、Ruby Hash文字列として安全にパースを試行
      # evalの代わりにYAMLを使用して安全にパース
      begin
        if data_string.start_with?('{') && data_string.end_with?('}')
          # Ruby Hash文字列をYAML形式に変換してパース
          # ただし、これも完全に安全ではないため、JSON以外は受け付けない方針とする
          Rails.logger.warn "Non-JSON data_string received: #{data_string[0..100]}..."
          return nil
        end
      rescue StandardError => e
        Rails.logger.error "Failed to parse data_string: #{e.message}"
      end
    end

    nil
  end

  # 画像URL抽出ヘルパー
  def extract_image_url(image_data)
    return nil if image_data.blank?

    case image_data
    when String
      image_data
    when Hash
      image_data['url'] || image_data['href']
    when Array
      image_data.first&.dig('url') || image_data.first&.dig('href')
    end
  end

  # RSA鍵ペア生成
  def generate_key_pair
    return unless local? && private_key.blank?

    rsa_key = OpenSSL::PKey::RSA.new(2048)

    self.private_key = rsa_key.to_pem
    self.public_key = rsa_key.public_key.to_pem
  end

  # ActivityPub URL設定
  def set_ap_urls
    return unless local?

    set_primary_ap_urls
    set_collection_ap_urls
  end

  # ローカルアクター数制限（SQLiteトリガーと連携）
  def local_actor_limit
    return unless local?

    local_count = Actor.where(local: true).where.not(id: id).count

    return unless local_count >= 2

    errors.add(:local, 'Maximum number of local accounts reached')
  end

  # すべてのローカルユーザを自動的にadminにする
  def set_admin_for_local_users
    self.admin = true if local?
  end

  def set_primary_ap_urls
    base_url = Rails.application.config.activitypub.base_url
    user_base = "#{base_url}/users/#{username}"

    self.ap_id ||= user_base
    self.inbox_url ||= "#{user_base}/inbox"
    self.outbox_url ||= "#{user_base}/outbox"
  end

  def set_collection_ap_urls
    base_url = Rails.application.config.activitypub.base_url
    user_base = "#{base_url}/users/#{username}"

    self[:followers_url] ||= "#{user_base}/followers"
    self[:following_url] ||= "#{user_base}/following"
    self.featured_url ||= "#{user_base}/collections/featured"
  end

  public

  # フォロー実行
  def follow!(target_actor_or_uri)
    result = FollowInteractor.follow(self, target_actor_or_uri)
    result.success? ? result.follow : nil
  end

  # アンフォロー実行
  def unfollow!(target_actor_or_uri)
    ActorActivityDistributor.new(self).unfollow!(target_actor_or_uri)
  end

  private

  # プロフィール更新を検知
  def should_distribute_profile_update?
    ActorActivityDistributor.new(self).should_distribute_profile_update?
  end

  # プロフィール更新を配信
  def distribute_profile_update
    ActorActivityDistributor.new(self).distribute_profile_update
  end
end
