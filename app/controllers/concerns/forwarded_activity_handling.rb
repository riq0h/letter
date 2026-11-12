# frozen_string_literal: true

# 転送されたアクティビティ(HTTP署名の主≠actor)の扱い。
# 転送者の署名は「転送者が送った」ことしか証明せず、actor本人が書いたことは証明しない。
# Mastodonは本人の署名(LD署名・FEP-8b32)を検証できない転送を破棄する。letterはそれらの
# 署名検証を持たないため、本文は使わず次のように扱う:
# - Create: 投稿を元のサーバから取り直して取り込む(リプライ転送の取りこぼしを防ぐ)
# - それ以外(Delete/Update/Like/Follow等): 本人の操作と確認できないので無視する
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
      FetchForwardedObjectJob.perform_later(object_uri, actor_uri)
      Rails.logger.info "🔀 Forwarded Create by #{@forwarded_by}: fetching #{object_uri} from its origin"
    else
      Rails.logger.info "🔀 Ignored forwarded #{@activity['type']} by #{@forwarded_by} (cannot verify #{actor_uri})"
    end

    head :accepted
  end
end
