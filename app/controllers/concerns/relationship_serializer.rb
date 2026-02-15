# frozen_string_literal: true

module RelationshipSerializer
  extend ActiveSupport::Concern

  private

  def serialized_relationship(account)
    return {} unless current_user

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
