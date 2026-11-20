# frozen_string_literal: true

require 'rails_helper'

# 署名付きのアクティビティが届いたサーバは動いているので、配送の失敗記録を消して配送を再開する
RSpec.describe 'Resuming delivery to a server that sends us activities', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end
  let(:activity) do
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}#delete-1",
      'type' => 'Delete', 'actor' => remote.ap_id, 'object' => 'https://remote.example.com/notes/unknown' }.to_json
  end

  before do
    allow(HttpSignatureVerifier).to receive(:new).and_return(verifier)
    create(:unavailable_server, domain: 'remote.example.com', first_error_at: 20.days.ago, last_error_at: 1.day.ago)
  end

  it 'clears the failure record of the sending server' do
    post '/inbox', params: activity, headers: headers

    expect(response).to have_http_status(:accepted)
    expect(UnavailableServer.exists?(domain: 'remote.example.com')).to be false
  end

  it 'keeps the record when the signature cannot be verified' do
    allow(verifier).to receive(:verify!).and_return(false)

    post '/inbox', params: activity, headers: headers

    expect(response).to have_http_status(:unauthorized)
    expect(UnavailableServer.exists?(domain: 'remote.example.com')).to be true
  end
end
