# frozen_string_literal: true

# username@domainが同じだがap_idが異なるアクターの衝突を解決するconcern
# アカウント削除後の再作成などで発生するケースに対応
module ActorIdentityResolver
  extend ActiveSupport::Concern

  def resolve_actor_identity_conflict(ap_id, username, domain, attributes)
    existing = Actor.find_by(username: username, domain: domain)
    return nil unless existing
    return nil if existing.ap_id == ap_id

    Rails.logger.info "Actor identity change detected: #{username}@#{domain} " \
                      "old_ap_id=#{existing.ap_id} new_ap_id=#{ap_id}"

    existing.update!(attributes.merge(ap_id: ap_id))
    existing
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to update actor identity: #{e.message}"
    nil
  end
end
