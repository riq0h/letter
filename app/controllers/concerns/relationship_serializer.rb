# frozen_string_literal: true

module RelationshipSerializer
  extend ActiveSupport::Concern

  private

  def serialized_relationship(account)
    return {} unless current_user

    if defined?(@relationship_cache) && @relationship_cache
      build_relationship_from_cache(account)
    else
      build_relationship_with_queries(account)
    end
  end

  # 複数アカウントのrelationshipデータを一括プリロード
  def preload_relationships(account_ids)
    return if account_ids.blank? || current_user.nil?

    @relationship_cache = {
      following: Follow.where(actor: current_user, target_actor_id: account_ids).index_by(&:target_actor_id),
      followed_by: Follow.where(actor_id: account_ids, target_actor: current_user).index_by(&:actor_id),
      blocking: current_user.blocks.where(target_actor_id: account_ids).pluck(:target_actor_id).to_set,
      blocked_by: current_user.blocked_by.where(actor_id: account_ids).pluck(:actor_id).to_set,
      muting: current_user.mutes.where(target_actor_id: account_ids).index_by(&:target_actor_id),
      domain_blocking: current_user.domain_blocks.pluck(:domain).to_set,
      notes: current_user.account_notes.where(target_actor_id: account_ids).index_by(&:target_actor_id)
    }
  end

  def build_relationship_from_cache(account)
    following_rel = @relationship_cache[:following][account.id]
    followed_by_rel = @relationship_cache[:followed_by][account.id]
    mute = @relationship_cache[:muting][account.id]
    note = @relationship_cache[:notes][account.id]
    following = following_rel&.accepted? || false

    {
      id: account.id.to_s,
      following: following,
      showing_reblogs: following,
      notifying: false,
      followed_by: followed_by_rel&.accepted? || false,
      blocking: @relationship_cache[:blocking].include?(account.id),
      blocked_by: @relationship_cache[:blocked_by].include?(account.id),
      muting: mute.present?,
      muting_notifications: mute&.notifications || false,
      requested: following_rel&.pending? || false,
      requested_by: followed_by_rel.present? && !followed_by_rel.accepted?,
      domain_blocking: account.domain.present? && @relationship_cache[:domain_blocking].include?(account.domain),
      endorsed: false,
      languages: nil,
      note: note&.comment || ''
    }
  end

  def build_relationship_with_queries(account)
    following_relationship = Follow.find_by(actor: current_user, target_actor: account)
    followed_by_relationship = Follow.find_by(actor: account, target_actor: current_user)
    mute = current_user.mutes.find_by(target_actor: account)
    note = current_user.account_notes.find_by(target_actor: account)
    following = following_relationship&.accepted? || false

    {
      id: account.id.to_s,
      following: following,
      showing_reblogs: following,
      notifying: false,
      followed_by: followed_by_relationship&.accepted? || false,
      blocking: current_user.blocking?(account),
      blocked_by: current_user.blocked_by?(account),
      muting: current_user.muting?(account),
      muting_notifications: mute&.notifications || false,
      requested: following_relationship&.pending? || false,
      requested_by: followed_by_relationship.present? && !followed_by_relationship.accepted?,
      domain_blocking: account.domain.present? ? current_user.domain_blocking?(account.domain) : false,
      endorsed: false,
      languages: nil,
      note: note&.comment || ''
    }
  end
end
