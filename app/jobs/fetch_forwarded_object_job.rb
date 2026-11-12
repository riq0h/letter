# frozen_string_literal: true

# 転送(署名者≠actor)やリレー経由で届いたCreateの投稿を、元のサーバから取り直して取り込むジョブ。
# 転送されてきた本文は転送者しか署名しておらず、作者本人のものと確認できないため使わない。
# 投稿のidから直接取得し(idと取得元の一致を検証)、作者が名乗られた本人であることを確かめてから、
# 作者本人から直接届いた場合と同じ処理(CreateActivityOrganizer)に渡す。
class FetchForwardedObjectJob < ApplicationJob
  queue_as :default

  def perform(object_uri, claimed_actor_uri, relay_id = nil)
    return if ActivityPubObject.exists?(ap_id: object_uri)
    return unless ActivityPubOrigin.same_host?(object_uri, claimed_actor_uri)

    object = ActivityPubHttpClient.fetch_verified(object_uri)
    return unless object.is_a?(Hash) && object['id'] == object_uri

    author_uri = ActivityPubOrigin.value_or_id(object['attributedTo'])
    unless author_uri == claimed_actor_uri
      Rails.logger.warn "🛡️ Forwarded object #{object_uri}: author #{author_uri.inspect} differs from claimed #{claimed_actor_uri}"
      return
    end

    author = Actor.find_by(ap_id: author_uri) || ActorFetcher.new.fetch_and_create(author_uri)
    return unless author

    activity = {
      'type' => 'Create', 'actor' => author_uri, 'object' => object,
      'to' => object['to'], 'cc' => object['cc']
    }
    result = CreateActivityOrganizer.call(activity, author, preserve_relay_info: relay_id && Relay.find_by(id: relay_id))
    Rails.logger.info "🔀 Forwarded object #{object_uri} imported from its origin" if result.success? && result.object
  end
end
