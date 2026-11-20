# frozen_string_literal: true

# 他サーバで削除されたアカウントを、その投稿などと一緒に消す。
# 投稿やブーストが数万件あるアカウントでもDBの書き込みロックを長く握らないよう、
# 件数の多くなりうるものは1件ずつ別のトランザクションで消し、一定件数ごとに間を空ける
class DeleteRemoteActorJob < ApplicationJob
  queue_as :low_priority

  # 同じアカウントの削除通知が重ねて届いても、処理は1つずつ行う
  limits_concurrency to: 1, key: ->(actor_id) { actor_id }, duration: 1.hour

  BATCHED_ASSOCIATIONS = %i[objects reblogs favourites activities mentions media_attachments].freeze
  BATCH_SIZE = 50
  PAUSE_BETWEEN_BATCHES = 0.2

  def perform(actor_id)
    actor = Actor.find_by(id: actor_id)
    return if actor.nil? || actor.local?

    BATCHED_ASSOCIATIONS.each { |name| destroy_in_batches(actor.public_send(name)) }
    HomeFeedManager.remove_by_actor(actor.id)
    with_database_lock_retry { actor.destroy! }

    Rails.logger.info "🗑️ Remote account deleted: #{actor.ap_id}"
  end

  private

  def destroy_in_batches(relation)
    relation.in_batches(of: BATCH_SIZE) do |batch|
      batch.each do |record|
        HomeFeedManager.remove_by_object(record.id) if record.is_a?(ActivityPubObject)
        with_database_lock_retry { record.destroy! }
      end
      sleep PAUSE_BETWEEN_BATCHES
    end
  end
end
