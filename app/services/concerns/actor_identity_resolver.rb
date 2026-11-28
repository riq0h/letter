# frozen_string_literal: true

# アクターを登録しようとして既存のアクターとぶつかったときに、代わりに使うアクターを決めるconcern
# - 同じap_idのアクターがもうある: 同じアカウントについての別のリクエストが同時に登録したもの。そのまま使う
# - username@domainが同じでap_idが異なる: アカウント削除後の再作成など。既存のアクターを新しいap_idに付け替える
module ActorIdentityResolver
  extend ActiveSupport::Concern

  def resolve_actor_identity_conflict(ap_id, username, domain, attributes)
    registered = Actor.find_by(ap_id: ap_id)
    return registered if registered

    existing = Actor.find_by(username: username, domain: domain)
    return nil unless existing

    Rails.logger.info "Actor identity change detected: #{username}@#{domain} " \
                      "old_ap_id=#{existing.ap_id} new_ap_id=#{ap_id}"

    existing.update!(attributes.merge(ap_id: ap_id))
    existing
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to update actor identity: #{e.message}"
    nil
  end
end
