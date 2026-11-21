# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Quote requests from other servers', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:local_actor) { create(:actor) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end

  def activity(type, object, extra = {})
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}/activities/1",
      'type' => type, 'actor' => remote.ap_id, 'object' => object }.merge(extra).to_json
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  it 'answers a quote request in the background' do
    quoted = create(:activity_pub_object, actor: local_actor)

    expect do
      post "/users/#{local_actor.username}/inbox",
           params: activity('QuoteRequest', quoted.ap_id, 'instrument' => "#{remote.ap_id}/statuses/1"), headers: headers
    end.to have_enqueued_job(ProcessQuoteRequestJob).with(hash_including('type' => 'QuoteRequest'), remote.id)

    expect(response).to have_http_status(:accepted)
  end

  describe 'GET /quote_auth/:id' do
    it 'serves the authorization to ActivityPub clients' do
      quoted = create(:activity_pub_object, actor: local_actor)
      quoting = create(:activity_pub_object, :remote, actor: remote)
      quote_post = QuotePost.create!(actor: remote, object: quoting, quoted_object: quoted, ap_id: "#{quoting.ap_id}#quote")
      path = URI(quote_post.quote_authorization.ap_id).path

      get path, headers: { 'Accept' => 'application/activity+json' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/activity+json')
      body = ActiveSupport::JSON.decode(response.body)
      expect(body).to include('type' => 'QuoteAuthorization', 'interactingObject' => quoting.ap_id,
                              'interactionTarget' => quoted.ap_id)
    end
  end
end
