# frozen_string_literal: true

class Follow < ApplicationRecord
  # === バリデーション ===
  validates :ap_id, presence: true, uniqueness: true
  validates :follow_activity_ap_id, presence: true

  # 自分自身をフォローできない
  validate :cannot_follow_self

  # === アソシエーション ===
  belongs_to :actor, inverse_of: :follows
  belongs_to :target_actor, class_name: 'Actor', inverse_of: :reverse_follows

  # === スコープ ===
  scope :accepted, -> { where(accepted: true) }
  scope :pending, -> { where(accepted: false) }
  scope :local, -> { joins(:actor).where(actors: { local: true }) }
  scope :remote, -> { joins(:actor).where(actors: { local: false }) }
  scope :recent, -> { order(created_at: :desc) }

  # 特定のアクターのフォロー関係
  scope :for_actor, ->(actor) { where(actor: actor) }
  scope :targeting_actor, ->(actor) { where(target_actor: actor) }

  # === コールバック ===
  before_validation :set_defaults, on: :create
  after_create :send_follow_activity, if: :should_send_follow_activity?
  after_create :update_follower_counts, if: :accepted?
  after_update :update_follower_counts, if: :saved_change_to_accepted?
  after_destroy :update_follower_counts_on_destroy

  # === 状態管理メソッド ===

  def accepted?
    accepted
  end

  def pending?
    !accepted
  end

  def local_follow?
    actor.local?
  end

  def remote_follow?
    !actor.local?
  end

  def accept!
    return if accepted?

    update!(
      accepted: true,
      accepted_at: Time.current
    )

    # Accept アクティビティを作成（ローカルユーザが承認する場合）
    create_accept_activity if target_actor.local?
  end

  def reject!
    return unless pending?

    # Reject アクティビティを作成（ローカルユーザが拒否する場合）
    create_reject_activity if target_actor.local?

    destroy
  end

  def unfollow!
    # Undo アクティビティを作成（ローカルユーザがフォロー解除する場合）
    create_undo_activity if actor.local?

    destroy
  end

  # === ActivityPub関連メソッド ===

  def activitypub_url
    ap_id
  end

  def follow_activity_url
    follow_activity_ap_id
  end

  def accept_activity_url
    accept_activity_ap_id
  end

  def create_accept_activity
    activity = Activity.create!(
      ap_id: generate_accept_activity_id,
      activity_type: 'Accept',
      actor: target_actor,
      target_ap_id: follow_activity_ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )

    # Accept アクティビティを外部に送信
    SendAcceptJob.perform_later(self)

    activity
  end

  private

  def set_defaults
    set_activity_ids
    set_default_accepted_status
    auto_accept_local_follows
  end

  def set_activity_ids
    self.ap_id = generate_follow_ap_id if ap_id.blank?
    self.follow_activity_ap_id = ap_id if follow_activity_ap_id.blank?
  end

  def set_default_accepted_status
    self.accepted = false if accepted.nil?
  end

  def auto_accept_local_follows
    return unless should_auto_accept?

    self.accepted = true
    self.accepted_at = Time.current
  end

  def should_auto_accept?
    actor&.local? && target_actor&.local? && !target_actor.manually_approves_followers
  end

  def cannot_follow_self
    return unless actor_id == target_actor_id

    errors.add(:target_actor, "can't follow yourself")
  end

  def update_follower_counts
    return unless accepted?

    # 非同期でカウンターを更新
    UpdateFollowerCountsJob.perform_later(actor.id, target_actor.id)
  rescue StandardError => e
    Rails.logger.error "Failed to update follower counts: #{e.message}"
    # 同期的にフォールバック
    update_follower_counts_sync
  end

  def update_follower_counts_on_destroy
    return unless accepted?

    # 削除処理中のfrozenオブジェクトを避けるため、IDを保存
    actor_id = actor.id
    target_actor_id = target_actor.id

    UpdateFollowerCountsJob.perform_later(actor_id, target_actor_id)
  rescue StandardError => e
    Rails.logger.error "Failed to update follower counts: #{e.message}"
    update_follower_counts_sync
  end

  def update_follower_counts_sync
    # 削除処理中のfrozenオブジェクトを避けるため、IDから再取得
    actor_record = Actor.find(actor_id)
    target_actor_record = Actor.find(target_actor_id)

    actor_record.update_following_count!
    target_actor_record.update_followers_count!
  rescue StandardError => e
    Rails.logger.error "Failed to sync follower counts: #{e.message}"
  end

  def create_reject_activity
    Activity.create!(
      ap_id: generate_reject_activity_id,
      activity_type: 'Reject',
      actor: target_actor,
      target_ap_id: follow_activity_ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )
  end

  def create_undo_activity
    activity = Activity.create!(
      ap_id: generate_undo_activity_id,
      activity_type: 'Undo',
      actor: actor,
      target_ap_id: follow_activity_ap_id,
      published_at: Time.current,
      local: true,
      processed: true
    )

    # Undo アクティビティを外部に送信
    SendActivityJob.perform_later(activity.id, [target_actor.inbox_url]) if target_actor && !target_actor.local?

    activity
  end

  def generate_accept_activity_id
    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end

  def generate_reject_activity_id
    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end

  def generate_undo_activity_id
    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end

  def generate_follow_ap_id
    return unless actor&.local?

    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end

  def should_send_follow_activity?
    # ローカルユーザが外部ユーザをフォローする場合のみ送信
    actor&.local? && target_actor && !target_actor.local?
  end

  def send_follow_activity
    Rails.logger.info "📤 Creating and queuing Follow activity for follow #{id}"

    # Activityレコードを作成
    Activity.create!(
      ap_id: follow_activity_ap_id,
      activity_type: 'Follow',
      actor: actor,
      target_ap_id: target_actor.ap_id,
      published_at: Time.current,
      local: true,
      processed: false
    )

    SendFollowJob.perform_later(self)
  end
end
