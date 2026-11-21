# frozen_string_literal: true

require 'rails_helper'

# こちらが送った引用の承認リクエストへの、作者のサーバからの応答
RSpec.describe 'Answers to our quote requests', type: :request do
  let(:me) { create(:actor) }
  let(:author) { create(:actor, :remote) }
  let(:quote_post) do
    my_post = create(:activity_pub_object, actor: me)
    QuotePost.create!(actor: me, object: my_post, quoted_object: create(:activity_pub_object, :remote, actor: author),
                      ap_id: "#{my_post.ap_id}#quote")
  end
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{author.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end
  let(:authorization_uri) { "#{author.ap_id}/quote_authorizations/1" }

  def answer(type, object, extra = {})
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{author.ap_id}#answers/1",
      'type' => type, 'actor' => author.ap_id, 'object' => object }.merge(extra).to_json
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  it 'hands an Accept with an embedded QuoteRequest to the job' do
    request_object = { 'id' => quote_post.quote_request_ap_id, 'type' => 'QuoteRequest' }

    expect { post "/users/#{me.username}/inbox", params: answer('Accept', request_object, 'result' => authorization_uri), headers: headers }
      .to have_enqueued_job(ProcessQuoteRequestAnswerJob).with(quote_post.id, 'Accept', author.id, authorization_uri)

    expect(response).to have_http_status(:accepted)
  end

  it 'hands a Reject naming the request by id to the job' do
    expect { post '/inbox', params: answer('Reject', quote_post.quote_request_ap_id), headers: headers }
      .to have_enqueued_job(ProcessQuoteRequestAnswerJob).with(quote_post.id, 'Reject', author.id, nil)
  end

  it 'treats deleting the authorization as revoking the approval' do
    quote_post.update!(quote_authorization_url: authorization_uri)

    expect { post '/inbox', params: answer('Delete', authorization_uri), headers: headers }
      .to have_enqueued_job(ProcessQuoteRequestAnswerJob).with(quote_post.id, 'Revoke', author.id)
  end
end
