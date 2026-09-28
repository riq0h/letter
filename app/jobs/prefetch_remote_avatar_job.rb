# frozen_string_literal: true

# アバター未取り込みのリモートアクターについて、元URLの到達確認を先回りで行うジョブ。
# 到達不可ならActorImageProcessor#avatar_urlが再取得ジョブ(RefreshRemoteActorJob)を投入する。
# 受信時にActorImageProcessor#enqueue_avatar_prefetchから24hに1回だけ投入される。
class PrefetchRemoteAvatarJob < ApplicationJob
  queue_as :default

  def perform(actor_id)
    actor = Actor.find_by(id: actor_id, local: false)
    return if actor.nil? || actor.avatar.attached?

    actor.avatar_url
  end
end
