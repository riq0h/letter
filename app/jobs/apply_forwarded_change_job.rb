# frozen_string_literal: true

# 転送されてきた(署名者≠actor。リレー経由など)投稿のUpdate/Deleteを、元のサーバで確かめて反映するジョブ。
# 転送された本文は転送者しか署名しておらず作者本人のものと確認できないため使わず、手元の投稿を元のサーバから取り直す。
# - Delete: 元のサーバが投稿のURL自身で「無い」(404/410、またはTombstone)と答えたときだけ削除する
# - Update: 取り直した最新の内容を、作者本人から直接届いたUpdateと同じ処理で反映する
# 対象は誰でも見られる投稿(公開・未収載)に限る。それ以外は見る権限がないだけでも404になりうるので、削除と取り違えない
class ApplyForwardedChangeJob < ApplicationJob
  include ActivityPubObjectHandlers

  queue_as :default

  REFETCHABLE_VISIBILITIES = %w[public unlisted].freeze

  def perform(activity_type, object_uri, claimed_actor_uri)
    object = ActivityPubObject.find_by(ap_id: object_uri, local: false)
    return unless object && object.actor&.ap_id == claimed_actor_uri
    return unless REFETCHABLE_VISIBILITIES.include?(object.visibility)

    client = ActivityPubHttpClient.new
    data = client.fetch_verified(object_uri, signing_actor: Actor.find_by(local: true))

    case activity_type
    when 'Delete' then delete_if_gone(object, data, client.gone?(object_uri))
    when 'Update' then apply_update(object, data)
    end
  end

  private

  def delete_if_gone(object, data, gone)
    unless gone || tombstone?(data)
      Rails.logger.info "🔀 Forwarded Delete of #{object.ap_id} not confirmed at its origin; kept"
      return
    end

    HomeFeedManager.remove_by_object(object.id)
    object.destroy!
    Rails.logger.info "🗑️ Object deleted (confirmed at its origin): #{object.ap_id}"
  end

  def apply_update(object, data)
    return unless data.is_a?(Hash) && data['id'] == object.ap_id && !tombstone?(data)
    return unless ActivityPubOrigin.value_or_id(data['attributedTo']) == object.actor.ap_id

    @sender = object.actor
    update_object_content(data)
  end

  def tombstone?(data)
    data.is_a?(Hash) && data['type'] == 'Tombstone'
  end
end
