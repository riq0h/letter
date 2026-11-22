# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Account moves from other servers', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:local_actor) { create(:actor) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end
  let(:target_uri) { 'https://new.example/users/kana' }

  def move(object)
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}#moves/1",
      'type' => 'Move', 'actor' => remote.ap_id, 'object' => object, 'target' => target_uri }.to_json
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  it 'moves the follows in the background' do
    expect do
      post "/users/#{local_actor.username}/inbox", params: move(remote.ap_id), headers: headers
    end.to have_enqueued_job(ProcessAccountMoveJob).with(remote.id, target_uri)

    expect(response).to have_http_status(:accepted)
  end

  it 'accepts moves on the shared inbox too' do
    expect { post '/inbox', params: move(remote.ap_id), headers: headers }
      .to have_enqueued_job(ProcessAccountMoveJob).with(remote.id, target_uri)
  end

  it 'ignores a move of some other account' do
    expect do
      post "/users/#{local_actor.username}/inbox", params: move('https://remote.example.com/users/someone-else'),
                                                   headers: headers
    end.not_to have_enqueued_job(ProcessAccountMoveJob)

    expect(response).to have_http_status(:accepted)
  end
end
