# frozen_string_literal: true

class ActivityPubObject < ApplicationRecord
  include SnowflakeIdGeneration
  include RemoteLocalHelper
  include ActionView::Helpers::SanitizeHelper
  include TextLinkingHelper

  self.table_name = 'objects'

  # === 定数 ===
  OBJECT_TYPES = %w[Note Article Image Video Audio Document Page Question Vote].freeze
  VISIBILITY_LEVELS = %w[public unlisted private direct].freeze

  # === バリデーション ===
  validates :ap_id, presence: true, uniqueness: true
  validates :object_type, presence: true, inclusion: { in: OBJECT_TYPES }
  validates :visibility, inclusion: { in: VISIBILITY_LEVELS }
  validates :published_at, presence: true
  validates :content, presence: true, if: :requires_content?
  validates :content, length: { maximum: 10_000 }

  # === アソシエーション ===
  belongs_to :actor, inverse_of: :objects
  belongs_to :relay, optional: true
  has_many :activities, dependent: :destroy, foreign_key: :object_ap_id, primary_key: :ap_id, inverse_of: :object
  has_many :favourites, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :reblogs, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :media_attachments, dependent: :destroy, inverse_of: :object, foreign_key: :object_id, primary_key: :id
  has_many :object_tags, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :tags, through: :object_tags
  has_many :mentions, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :mentioned_actors, through: :mentions, source: :actor
  has_many :bookmarks, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :status_edits, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :quote_posts, dependent: :destroy, foreign_key: :object_id, inverse_of: :object
  has_many :quotes_of_this, class_name: 'QuotePost', dependent: :destroy, foreign_key: :quoted_object_id, inverse_of: :quoted_object
  has_one :poll, dependent: :destroy, foreign_key: :object_id, primary_key: :id, inverse_of: :object

  # 会話（ダイレクトメッセージ用）
  belongs_to :conversation, optional: true

  # === スコープ ===
  scope :local, -> { where(local: true) }
  scope :remote, -> { where(local: false) }
  scope :public_posts, -> { where(visibility: 'public') }
  scope :unlisted, -> { where(visibility: 'unlisted') }
  scope :recent, -> { order(published_at: :desc) }
  scope :by_type, ->(type) { where(object_type: type) }
  scope :notes, -> { by_type('Note') }
  scope :articles, -> { by_type('Article') }
  scope :with_media, -> { joins(:media_attachments) }
  scope :without_replies, -> { where(in_reply_to_ap_id: nil) }

  # 会話関係
  scope :in_conversation, ->(conversation_id) { where(conversation_ap_id: conversation_id) }

  # === コールバック ===
  before_validation :set_defaults, on: :create
  before_validation :generate_snowflake_id, on: :create
  before_save :extract_plaintext
  before_save :set_conversation_id
  after_create :process_text_content, if: -> { content.present? }
  after_create :update_actor_posts_count, if: -> { local? && object_type == 'Note' }
  after_create :deliver_to_streaming, if: -> { object_type == 'Note' }
  after_update :process_text_content, if: -> { local? && saved_change_to_content? }
  after_destroy :create_delete_activity, if: :local?
  after_destroy :update_actor_posts_count, if: -> { local? && object_type == 'Note' }
  after_save :create_activity_if_needed, if: :local?
  after_commit :enqueue_relay_distribution, on: :create, if: -> { local? && should_distribute_to_relays? }

  # === URL生成メソッド ===
  def public_url
    ActivityPubContentProcessor.new(self).public_url
  end

  def activitypub_url
    ap_id
  end

  # === ActivityPub関連メソッド ===

  def local?
    local
  end

  def public?
    visibility == 'public'
  end

  def unlisted?
    visibility == 'unlisted'
  end

  def private?
    visibility == 'private'
  end

  def direct?
    visibility == 'direct'
  end

  def sensitive?
    sensitive
  end

  # === コンテンツ関連メソッド ===

  def note?
    object_type == 'Note'
  end

  def article?
    object_type == 'Article'
  end

  def media?
    media_attachments.any?
  end

  def reply?
    in_reply_to_ap_id.present?
  end

  def edited?
    edited_at.present?
  end

  def edits_count
    status_edits.count
  end

  def quotes_count
    quotes_of_this.count
  end

  def quoted?
    quote_posts.any?
  end

  def root_conversation
    return self unless reply?

    current = self
    current = current.in_reply_to while current.in_reply_to.present?
    current
  end

  def conversation_thread
    return ActivityPubObject.where(id: id) if conversation_ap_id.blank?

    ActivityPubObject.in_conversation(conversation_ap_id).recent
  end

  # === ActivityPub JSON-LD出力 ===

  def to_activitypub
    ActivityPubObjectSerializer.new(self).to_activitypub
  end

  # === 表示用メソッド ===

  def display_content
    ActivityPubContentProcessor.new(self).display_content
  end

  def truncated_content(length = 500)
    return '' if content_plaintext.blank?

    if content_plaintext.length > length
      "#{content_plaintext[0, length]}..."
    else
      content_plaintext
    end
  end

  def formatted_content
    return '' if content.blank?

    # HTMLサニタイズ済みコンテンツとして扱う
    ActionController::Base.helpers.sanitize(content, tags: %w[p br strong em a],
                                                     attributes: %w[href])
  end

  def build_activitypub_content
    return content if content.blank?

    # 既存のTextLinkingHelperを使ってURLとメンションをリンク化
    auto_link_urls(content)
  end

  # 編集前のスナップショットを作成
  def create_edit_snapshot!
    StatusEdit.create_snapshot(self)
  end

  # 編集を実行
  def perform_edit!(params)
    # 編集前の状態を保存
    create_edit_snapshot!

    update_attributes = {}
    update_attributes[:content] = params[:content] if params.key?(:content)
    update_attributes[:summary] = params[:summary] if params.key?(:summary)
    update_attributes[:sensitive] = params[:sensitive] if params.key?(:sensitive)
    update_attributes[:language] = params[:language] if params.key?(:language)
    update_attributes[:edited_at] = Time.current

    return false unless update(update_attributes)

    # メディア添付の更新
    if params.key?(:media_ids)
      if params[:media_ids].present? && params[:media_ids].any?
        # 既存のメディアと新しいメディアの両方を考慮
        existing_media = media_attachments.where(id: params[:media_ids])
        new_media = actor.media_attachments.where(id: params[:media_ids], object_id: nil)
        all_requested_media = (existing_media + new_media).uniq

        self.media_attachments = all_requested_media
      else
        # メディアIDが空の場合は関連付けを解除（レコードは保持）
        current_media = media_attachments.to_a
        current_media.each { |media| media.update!(object_id: nil) }
        association(:media_attachments).reset
      end
    end

    # 投票の更新処理
    update_poll_for_edit(params[:poll_options]) if params.key?(:poll_options)

    # ActivityPub配信用のUpdate活動を作成
    create_update_activity if local?

    true
  end

  # Quote活動を作成してActivityPub配信
  def create_quote_activity(quoted_object)
    ActivityPubActivityDistributor.new(self).create_quote_activity(quoted_object)
  end

  # 投票の編集処理
  def update_poll_for_edit(poll_options_param)
    if poll_options_param.present? && poll_options_param.any?
      # 投票を作成または更新
      if poll.present?
        # 既存の投票を更新
        poll.update!(
          options: poll_options_param.map { |option| { 'title' => option } },
          votes_count: 0,
          voters_count: 0
        )
        # 既存の投票を削除（編集では投票はリセット）
        poll.poll_votes.destroy_all
      else
        # 新しい投票を作成
        Poll.create!(
          object: self,
          options: poll_options_param.map { |option| { 'title' => option } },
          expires_at: 7.days.from_now, # デフォルト期限
          multiple: false,
          votes_count: 0,
          voters_count: 0
        )
      end
    else
      # 投票を削除
      poll&.destroy
    end
  end

  private

  # === ActivityPub ヘルパーメソッド ===

  def build_audience_list(type)
    ActivityBuilders::AudienceBuilder.new(self).build(type)
  end

  def build_attachment_list
    ActivityBuilders::AttachmentBuilder.new(self).build
  end

  def build_tag_list
    ActivityBuilders::TagBuilder.new(self).build
  end

  # === バリデーション・コールバックヘルパー ===

  def set_defaults
    set_timestamps
    set_local_flag
    set_visibility_and_language
    set_sensitivity
    set_ap_id_for_local
  end

  def set_timestamps
    self.published_at ||= Time.current
  end

  def set_local_flag
    self.local = actor&.local? if local.nil?
  end

  def set_visibility_and_language
    self.visibility ||= 'public'
    self.language ||= Rails.application.config.activitypub.default_locale
  end

  def set_sensitivity
    self.sensitive = false if sensitive.nil?
  end

  def set_ap_id_for_local
    return unless local? && ap_id.blank?

    # Snowflake IDが生成されていない場合は生成
    generate_snowflake_id if id.blank?

    self.ap_id = generate_ap_id
  end

  def generate_ap_id
    return unless local?

    "#{base_url}/users/#{actor.username}/posts/#{id}"
  end

  def base_url
    Rails.application.config.activitypub.base_url
  end

  def extract_plaintext
    return if content.blank?

    # HTMLタグを除去してプレーンテキストを抽出
    self.content_plaintext = ActionController::Base.helpers.strip_tags(content)
                                                   .gsub(/\s+/, ' ')
                                                   .strip
  end

  def set_conversation_id
    if reply? && conversation_ap_id.blank?
      set_reply_conversation_id
    elsif conversation_ap_id.blank?
      set_new_conversation_id
    end
  end

  def set_reply_conversation_id
    parent = ActivityPubObject.find_by(ap_id: in_reply_to_ap_id)
    self.conversation_ap_id = parent&.conversation_ap_id || in_reply_to_ap_id
  end

  def set_new_conversation_id
    self.conversation_ap_id = ap_id
  end

  def requires_content?
    return false if media_attachments.any?

    # Vote、Question、メディア付きオブジェクトはcontentが不要
    %w[Note Article].include?(object_type)
  end

  def create_activity_if_needed
    return unless saved_change_to_id? # 新規作成時のみ実行

    existing_activity = Activity.find_by(object_ap_id: ap_id, activity_type: 'Create')
    return existing_activity if existing_activity

    activity = Activity.create!(
      ap_id: "#{ap_id}#create",
      activity_type: 'Create',
      actor: actor,
      object_ap_id: ap_id,
      published_at: published_at,
      local: true
    )

    queue_activity_delivery(activity)
    activity
  end

  def create_delete_activity
    ActivityPubActivityDistributor.new(self).create_delete_activity
  end

  def process_text_content
    ActivityPubContentProcessor.new(self).process_text_content
  end

  def update_actor_posts_count
    actor.update_posts_count! if actor.present?
  rescue StandardError => e
    Rails.logger.error "Failed to update actor posts count: #{e.message}"
  end

  # Update活動を作成してActivityPub配信
  def create_update_activity
    activity = Activity.create!(
      ap_id: "#{ap_id}#update-#{Time.current.to_f}",
      activity_type: 'Update',
      actor: actor,
      object_ap_id: ap_id,
      published_at: Time.current,
      local: true
    )

    # ActivityPub配信をキューに追加
    queue_activity_delivery(activity)
  end

  # ActivityPub配信をキューする
  def queue_activity_delivery(activity)
    # メンションされたアクター（外部）のinboxは常に配信対象
    mentioned_inboxes = mentioned_actors.where(local: false).pluck(:inbox_url)
    all_inboxes = mentioned_inboxes.dup

    case visibility
    when 'public', 'unlisted', 'private'
      # Public/Unlisted/フォロワー限定：フォロワー + メンションされたアクター
      follower_inboxes = actor.followers.where(local: false).pluck(:inbox_url)
      all_inboxes.concat(follower_inboxes)
    when 'direct'
      # DM：メンションされたアクターのみ（既に all_inboxes に含まれている）
    end

    # 重複を除去して配信
    unique_inboxes = all_inboxes.uniq.compact
    SendActivityJob.perform_later(activity.id, unique_inboxes) if unique_inboxes.any?
  end

  # === リレー配信関連 ===

  def should_distribute_to_relays?
    return false unless object_type == 'Note'
    return false if visibility == 'direct'
    return false if visibility == 'private'

    true
  end

  def enqueue_relay_distribution
    DistributeToRelaysJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error "💥 Relay distribution enqueue error: #{e.message}"
  end

  # === リアルタイムストリーミング配信 ===

  def deliver_to_streaming
    return unless object_type == 'Note'

    serialized_status = serialize_for_streaming

    # パブリックタイムラインへの即座配信
    if visibility == 'public'
      SseConnectionManager.instance.broadcast_to_stream('public', 'update', serialized_status)

      SseConnectionManager.instance.broadcast_to_stream('public:local', 'update', serialized_status) if local?

      # ハッシュタグストリーム配信
      broadcast_to_hashtag_streams(serialized_status)
    end

    # ホームタイムライン配信
    broadcast_to_home_timelines(serialized_status)

    # リストタイムライン配信
    broadcast_to_list_timelines(serialized_status)

    Rails.logger.info "📡 Status #{id} delivered to real-time streams (#{visibility})"
  rescue StandardError => e
    Rails.logger.error "💥 Streaming delivery error: #{e.message}"
  end

  def serialize_for_streaming
    {
      id: id.to_s,
      created_at: published_at&.iso8601,
      content: content || '',
      content_plaintext: content_plaintext || '',
      summary: summary,
      sensitive: sensitive?,
      visibility: visibility,
      language: language,
      url: public_url || ap_id,
      replies_count: replies_count || 0,
      reblogs_count: reblogs_count || 0,
      favourites_count: favourites_count || 0,
      account: serialize_actor_for_streaming,
      media_attachments: serialize_media_attachments_for_streaming,
      mentions: serialize_mentions_for_streaming,
      tags: serialize_tags_for_streaming,
      emojis: []
    }
  end

  def serialize_actor_for_streaming
    {
      id: actor.id.to_s,
      username: actor.username,
      acct: actor.acct,
      display_name: actor.display_name || actor.username,
      locked: actor.locked?,
      bot: actor.bot?,
      discoverable: actor.discoverable?,
      note: actor.note || '',
      url: actor.public_url || actor.ap_id,
      avatar: actor.avatar_url || '',
      header: actor.header_url || '',
      followers_count: actor.followers_count || 0,
      following_count: actor.following_count || 0,
      statuses_count: actor.posts_count || 0,
      created_at: actor.created_at.iso8601
    }
  end

  def serialize_media_attachments_for_streaming
    media_attachments.map do |media|
      {
        id: media.id.to_s,
        type: media.media_type,
        url: media.url,
        preview_url: media.preview_url,
        remote_url: media.remote_url,
        description: media.description,
        blurhash: media.blurhash
      }
    end
  end

  def serialize_mentions_for_streaming
    mentions.includes(:actor).map do |mention|
      {
        id: mention.actor.id.to_s,
        username: mention.actor.username,
        acct: mention.actor.acct,
        url: mention.actor.public_url || mention.actor.ap_id
      }
    end
  end

  def serialize_tags_for_streaming
    tags.map do |tag|
      {
        name: tag.name,
        url: "/tags/#{tag.name}"
      }
    end
  end

  def broadcast_to_hashtag_streams(serialized_status)
    tags.each do |tag|
      # グローバルハッシュタグ
      SseConnectionManager.instance.broadcast_to_hashtag(tag.name, 'update', serialized_status)

      # ローカルハッシュタグ（ローカル投稿のみ）
      SseConnectionManager.instance.broadcast_to_hashtag(tag.name, 'update', serialized_status, local_only: true) if local?
    end
  end

  def broadcast_to_home_timelines(serialized_status)
    # フォロワーのホームタイムラインに配信
    follower_ids = actor.followers.local.pluck(:id)

    follower_ids.each do |follower_id|
      SseConnectionManager.instance.broadcast_to_user(follower_id, 'update', serialized_status)
    end

    # 自分のホームタイムラインにも配信
    return unless actor.local?

    SseConnectionManager.instance.broadcast_to_user(actor_id, 'update', serialized_status)
  end

  def broadcast_to_list_timelines(serialized_status)
    # この投稿者をリストに含むすべてのリストに配信
    ListMembership.where(actor_id: actor_id).includes(:list).find_each do |membership|
      SseConnectionManager.instance.broadcast_to_list(membership.list_id, 'update', serialized_status)
    end
  end
end
