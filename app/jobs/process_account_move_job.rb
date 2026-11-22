# frozen_string_literal: true

# 他サーバのアカウントの引っ越し(Move)を処理する(Mastodonと同じ)。
# 引っ越し先のアカウントが元のアカウントを別名(alsoKnownAs)に挙げているときだけ本物の
# 引っ越しとみなす。こちらのユーザが元のアカウントをフォローしていれば引っ越し先をフォローし直して
# 元のフォローを外し、ブロック・ミュート・リストも引っ越し先に引き継ぐ
class ProcessAccountMoveJob < ApplicationJob
  queue_as :default

  def perform(old_actor_id, target_uri)
    old = Actor.find_by(id: old_actor_id)
    return if old.nil? || old.local? || target_uri.blank? || target_uri == old.ap_id

    target = fetch_target(target_uri)
    return Rails.logger.warn("🚚 Move of #{old.ap_id} ignored: #{target_uri} is unavailable") if target.nil? || target.local?
    return Rails.logger.warn("🚚 Move of #{old.ap_id} ignored: #{target.ap_id} does not list it as an alias") unless alias_of?(target, old)

    carry_over_blocks_and_mutes(old, target)
    move_follows(old, target)
    carry_over_list_memberships(old, target)
    Rails.logger.info "🚚 Moved #{old.ap_id} to #{target.ap_id}"
  end

  private

  # 別名の確認には最新の内容が要るので、既知のアカウントでも取り直す
  def fetch_target(uri)
    existing = Actor.find_by(ap_id: uri)
    return ActorFetcher.new.refresh(existing) if existing

    ActorFetcher.new.fetch_and_create(uri)
  end

  def alias_of?(target, old)
    data = JSON.parse(target.raw_data.to_s)
    Array.wrap(data['alsoKnownAs']).map { |entry| ActivityPubOrigin.value_or_id(entry) }.include?(old.ap_id)
  rescue JSON::ParserError
    false
  end

  def move_follows(old, target)
    Follow.where(target_actor: old).includes(:actor).find_each do |follow|
      local = follow.actor
      next unless local&.local?

      already = local.blocking?(target) || Follow.exists?(actor: local, target_actor: target)
      Follow.create!(actor: local, target_actor: target) unless already
      follow.unfollow!
    end
  end

  def carry_over_blocks_and_mutes(old, target)
    Block.where(target_actor: old).includes(:actor).find_each do |block|
      block.actor.blocks.find_or_create_by!(target_actor: target) if block.actor&.local?
    end
    Mute.where(target_actor: old).includes(:actor).find_each do |mute|
      mute.actor.mutes.find_or_create_by!(target_actor: target) if mute.actor&.local?
    end
  end

  def carry_over_list_memberships(old, target)
    ListMembership.where(actor: old).find_each do |membership|
      ListMembership.find_or_create_by!(list_id: membership.list_id, actor: target)
    end
  end
end
