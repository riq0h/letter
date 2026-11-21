# frozen_string_literal: true

# 他サーバの投稿を引用したとき、作者のサーバに承認を求める(FEP-044fのQuoteRequest。Mastodon 4.5以降)。
# 承認(Accept)が届くまで、Mastodonでは引用が承認待ちとして扱われる。
# 承認の仕組みを持たないサーバ(Misskeyなど)はこのリクエストを無視し、従来どおりの引用として表示する
class SendQuoteRequestJob < ApplicationJob
  class DeliveryFailed < StandardError; end

  queue_as :default

  # 相手サーバが応答しない・5xxなどの一時的な失敗は、間を空けて送り直す
  retry_on DeliveryFailed, wait: :polynomially_longer, attempts: 5

  def perform(quote_post_id)
    quote_post = QuotePost.find_by(id: quote_post_id)
    return if quote_post.nil? || quote_post.approved?

    requester = quote_post.actor
    author = quote_post.quoted_object&.actor
    return unless requester&.local? && author && !author.local?

    result = ActivitySender.new.send_activity(activity: payload(quote_post), target_inbox: author.inbox_url,
                                              signing_actor: requester)
    Rails.logger.info "💬 Quote request #{quote_post.quote_request_ap_id} sent (#{result[:success] ? 'ok' : result[:error]})"
    raise DeliveryFailed, result[:error].to_s if UnavailableServer.delivery_failure?(result)
  end

  private

  def payload(quote_post)
    {
      '@context' => ProcessQuoteRequestJob::CONTEXT,
      'id' => quote_post.quote_request_ap_id,
      'type' => 'QuoteRequest',
      'actor' => quote_post.actor.ap_id,
      'object' => quote_post.quoted_object.ap_id,
      'instrument' => quote_post.object.ap_id
    }
  end
end
