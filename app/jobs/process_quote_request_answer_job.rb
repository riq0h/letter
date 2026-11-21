# frozen_string_literal: true

# 他サーバの投稿を引用したときに送った承認リクエストへの、作者のサーバからの応答を処理する。
# 承認(Accept)なら、resultの承認の証明(QuoteAuthorization)を作者のサーバから取得して確かめてから
# 引用に記録し、投稿をUpdateとして配送し直す(ほかのサーバが承認済みの引用として表示できるように)。
# 拒否(Reject)や承認の取り消しなら、引用をやめて同じく配送し直す(投稿の本文はそのまま残す)
class ProcessQuoteRequestAnswerJob < ApplicationJob
  queue_as :default

  def perform(quote_post_id, answer, sender_id, authorization_uri = nil)
    quote_post = QuotePost.find_by(id: quote_post_id)
    return unless quote_post&.actor&.local?
    # 応答は引用された投稿の作者本人から届いたものだけを受け付ける
    return unless quote_post.quoted_object&.actor_id == sender_id

    case answer
    when 'Accept' then approve(quote_post, authorization_uri)
    when 'Reject', 'Revoke' then withdraw(quote_post)
    end
  end

  private

  def approve(quote_post, uri)
    return if quote_post.quote_authorization_url == uri
    return Rails.logger.warn("💬 Quote approval for #{quote_post.id} could not be verified: #{uri}") unless verified?(quote_post, uri)

    quote_post.update!(quote_authorization_url: uri)
    quote_post.object.redistribute!
    Rails.logger.info "💬 Quote #{quote_post.id} approved by #{quote_post.quoted_object.actor.ap_id}"
  end

  # 承認の証明が、引用された投稿の作者のサーバにあり、この引用を対象にしているか
  def verified?(quote_post, uri)
    author = quote_post.quoted_object.actor
    return false unless ActivityPubOrigin.same_host?(uri, author.ap_id)

    json = ActivityPubHttpClient.fetch_verified(uri, signing_actor: quote_post.actor)
    json.is_a?(Hash) && json['type'] == 'QuoteAuthorization' &&
      ActivityPubOrigin.value_or_id(json['attributedTo']) == author.ap_id &&
      ActivityPubOrigin.value_or_id(json['interactingObject']) == quote_post.object.ap_id &&
      ActivityPubOrigin.value_or_id(json['interactionTarget']) == quote_post.quoted_object.ap_id
  end

  def withdraw(quote_post)
    object = quote_post.object
    quote_post.destroy!
    object.redistribute!
    Rails.logger.info "💬 Quote of #{object.ap_id} withdrawn (rejected or revoked by the author)"
  end
end
