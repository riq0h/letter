# frozen_string_literal: true

# フォールバック状態（アバター到達不可）のリモートアクターを再取得し、
# プロフィール・raw_data・アバター/ヘッダー画像を最新化するジョブ。
# ActorImageProcessor から死活バックオフ付きで投入される。
class RefreshRemoteActorJob < ApplicationJob
  queue_as :default

  # ネットワーク失敗は ActorFetcher#refresh 内で握り潰す（nil返し）ため、
  # ここでの retry_on は不要。再試行は投入側の12hクールダウンが制御する。
  def perform(actor_id)
    actor = Actor.find_by(id: actor_id, local: false)
    return unless actor

    ActorFetcher.new.refresh(actor)
  end
end
