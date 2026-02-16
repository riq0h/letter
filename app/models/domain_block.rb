# frozen_string_literal: true

class DomainBlock < ApplicationRecord
  belongs_to :actor

  validates :domain, presence: true, uniqueness: { scope: :actor_id }
  validates :domain, format: { with: /\A[a-z0-9.-]+\.[a-z]{2,}\z/i }
  validate :cannot_block_local_domain

  before_validation :normalize_domain
  after_create :remove_followers_from_domain
  after_create :unfollow_accounts_from_domain

  scope :for_domain, ->(domain) { where(domain: domain) }

  private

  def normalize_domain
    self.domain = domain.strip.downcase if domain.present?
  end

  def cannot_block_local_domain
    local_domain = Rails.application.config.activitypub.domain
    return unless domain == local_domain

    errors.add(:domain, 'cannot block your own domain')
  end

  def remove_followers_from_domain
    # ブロックされたドメインからのフォロワーを削除
    follower_ids = actor.followers.where(domain: domain).pluck(:id)
    Follow.where(actor_id: follower_ids, target_actor: actor).destroy_all
  end

  def unfollow_accounts_from_domain
    # ブロックされたドメインのアカウントをすべてアンフォロー
    following_ids = actor.following.where(domain: domain).pluck(:id)
    Follow.where(actor: actor, target_actor_id: following_ids).destroy_all
  end
end
