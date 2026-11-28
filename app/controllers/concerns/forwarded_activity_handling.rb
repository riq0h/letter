# frozen_string_literal: true

# 転送されたアクティビティ(HTTP署名の主≠actor)の扱い。
# 転送者の署名は「転送者が送った」ことしか証明せず、actor本人が書いたことは証明しない。
# Mastodonは本人の署名(LD署名・FEP-8b32)を検証できない転送を破棄する。letterはそれらの
# 署名検証を持たないため、本文は使わず次のように扱う:
# - Create: 投稿を元のサーバから取り直して取り込む(リプライ転送の取りこぼしを防ぐ)
# - 購読しているリレーが中継したAnnounce: ブーストされた投稿だけを元のサーバから取り直して取り込む
#   (ブースト自体は本人のものと確かめられないので記録しない)
# - 手元にある投稿のUpdate/Delete: 元のサーバで今の状態を確かめて反映する(ApplyForwardedChangeJob)
# - それ以外(Like/Follow、手元にない投稿やアカウントのUpdate/Delete等): 本人の操作と確認できないので無視する
module ForwardedActivityHandling
  extend ActiveSupport::Concern

  private

  def forwarded_activity?
    @forwarded_by.present?
  end

  def handle_forwarded_activity
    object_uri = ActivityPubOrigin.value_or_id(@activity['object'])
    actor_uri = ActivityPubOrigin.value_or_id(@activity['actor'])

    if @activity['type'] == 'Create' && object_uri && actor_uri
      FetchForwardedObjectJob.perform_later(object_uri, actor_uri, forwarding_relay&.id)
      Rails.logger.info "🔀 Forwarded Create by #{@forwarded_by}: fetching #{object_uri} from its origin"
    elsif @activity['type'] == 'Announce' && object_uri && forwarding_relay
      FetchForwardedObjectJob.perform_later(object_uri, nil, forwarding_relay.id)
      Rails.logger.info "🔀 Relayed boost by #{actor_uri}: fetching #{object_uri} from its origin"
    elsif %w[Update Delete].include?(@activity['type']) && actor_uri && held_remote_object?(object_uri)
      ApplyForwardedChangeJob.perform_later(@activity['type'], object_uri, actor_uri)
      Rails.logger.info "🔀 Forwarded #{@activity['type']} by #{@forwarded_by}: checking #{object_uri} at its origin"
    else
      Rails.logger.info "🔀 Ignored forwarded #{@activity['type']} by #{@forwarded_by} (cannot verify #{actor_uri})"
    end

    head :accepted
  end

  def held_remote_object?(object_uri)
    object_uri.present? && ActivityPubObject.exists?(ap_id: object_uri, local: false)
  end

  # 中継したのが購読している(承認待ちを含む)リレーなら、そのリレー
  def forwarding_relay
    return @forwarding_relay if defined?(@forwarding_relay)

    @forwarding_relay = Relay.where(state: %w[accepted pending]).find { |relay| relay.actor_uri == @forwarded_by }
  end
end
