# frozen_string_literal: true

# 他サーバからの引用リクエスト(FEP-044fのQuoteRequest。Mastodon 4.5以降が送る)に応答する。
# 応答しないと、相手サーバでは引用が「承認待ち」のまま表示されない。
# 投稿の引用の許可設定(QuotePolicy)が相手を認めていれば承認(Accept)し、承認の証明
# (QuoteAuthorization)のURLを返す。認めていなければ拒否(Reject)する。
# 引用した投稿を取得できない・その投稿が実際には引用していない場合は、判断できないので応答しない
class ProcessQuoteRequestJob < ApplicationJob
  queue_as :default

  QUOTE_KEYS = %w[quote quoteUri quoteUrl _misskey_quote].freeze
  CONTEXT = [
    'https://www.w3.org/ns/activitystreams',
    { 'QuoteRequest' => 'https://w3id.org/fep/044f#QuoteRequest' }
  ].freeze

  def perform(request, requester_id)
    @request = request
    @requester = Actor.find_by(id: requester_id)
    return if @requester.nil? || @requester.local?

    @quoted = ActivityPubObject.find_by(ap_id: ActivityPubOrigin.value_or_id(request['object']))
    return unless @quoted&.local?

    return respond(reject_payload) unless approvable?

    quote_post = find_or_create_quote_post
    return Rails.logger.warn("💬 Quote request #{request['id']}: quoting post unavailable, not answering") unless quote_post

    respond(accept_payload(quote_post))
  end

  private

  def approvable?
    QuotePolicy.new(@quoted).for(@requester) == 'automatic'
  end

  def quoting_uri
    @quoting_uri ||= ActivityPubOrigin.value_or_id(@request['instrument'])
  end

  def find_or_create_quote_post
    return unless quoting_uri && ActivityPubOrigin.same_host?(quoting_uri, @requester.ap_id)

    quoting = ActivityPubObject.find_by(ap_id: quoting_uri) || import_quoting_post
    return unless quoting && quoting.actor_id == @requester.id && quotes_target?(quoting)

    quote_post = QuotePost.find_by(object: quoting, quoted_object: @quoted) || create_quote_post(quoting)
    align_authorization(quote_post, quoting)
    quote_post
  end

  # 引用した投稿を取り込む。取得できなければ、リクエストに埋め込まれた投稿(本人の署名付きで届いたもの)を使う
  def import_quoting_post
    json = ActivityPubHttpClient.fetch_verified(quoting_uri, signing_actor: @quoted.actor)
    json = @request['instrument'] if json.nil? && @request['instrument'].is_a?(Hash) && @request['instrument']['id'] == quoting_uri
    return unless json.is_a?(Hash) && ActivityPubOrigin.value_or_id(json['attributedTo']) == @requester.ap_id

    activity = { 'type' => 'Create', 'actor' => @requester.ap_id, 'object' => json, 'to' => json['to'], 'cc' => json['cc'] }
    CreateActivityOrganizer.call(activity, @requester)
    ActivityPubObject.find_by(ap_id: quoting_uri)
  end

  def quotes_target?(quoting)
    data = quoting.raw_data.is_a?(String) ? JSON.parse(quoting.raw_data) : quoting.raw_data
    return false unless data.is_a?(Hash)

    QUOTE_KEYS.any? { |key| ActivityPubOrigin.value_or_id(data[key]) == @quoted.ap_id }
  rescue JSON::ParserError
    false
  end

  def create_quote_post(quoting)
    QuotePost.create!(
      actor: quoting.actor,
      object: quoting,
      quoted_object: @quoted,
      shallow_quote: quoting.content.blank?,
      quote_text: quoting.content,
      visibility: quoting.visibility,
      ap_id: "#{quoting.ap_id}#quote"
    )
  end

  # 承認の証明は、引用した投稿そのものを対象にしていなければならない
  def align_authorization(quote_post, quoting)
    authorization = quote_post.quote_authorization
    authorization.update!(interacting_object_id: quoting.ap_id) if authorization.interacting_object_id != quoting.ap_id
  end

  def quote_request_object
    {
      'id' => @request['id'],
      'type' => 'QuoteRequest',
      'actor' => @requester.ap_id,
      'object' => @quoted.ap_id,
      'instrument' => quoting_uri
    }.compact
  end

  def accept_payload(quote_post)
    {
      '@context' => CONTEXT,
      'id' => "#{@quoted.actor.ap_id}#accepts/quote_requests/#{quote_post.id}",
      'type' => 'Accept',
      'actor' => @quoted.actor.ap_id,
      'to' => @requester.ap_id,
      'object' => quote_request_object,
      'result' => quote_post.quote_authorization.ap_id
    }
  end

  def reject_payload
    {
      '@context' => CONTEXT,
      'id' => "#{@quoted.actor.ap_id}#rejects/quote_requests/#{SecureRandom.hex(8)}",
      'type' => 'Reject',
      'actor' => @quoted.actor.ap_id,
      'to' => @requester.ap_id,
      'object' => quote_request_object
    }
  end

  def respond(payload)
    result = ActivitySender.new.send_activity(activity: payload, target_inbox: @requester.inbox_url,
                                              signing_actor: @quoted.actor)
    Rails.logger.info "💬 Quote request #{@request['id']}: #{payload['type']} sent (#{result[:success] ? 'ok' : result[:error]})"
  end
end
