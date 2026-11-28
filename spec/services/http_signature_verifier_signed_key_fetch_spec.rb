# frozen_string_literal: true

require 'rails_helper'

# 署名検証用の鍵(アクター文書)の取得
RSpec.describe HttpSignatureVerifier do
  let(:verifier) { described_class.new(method: 'POST', path: '/inbox', headers: {}, body: '') }
  let(:actor_uri) { 'https://origin.example/users/alice' }
  let(:http) { instance_double(Net::HTTP) }

  before do
    allow(verifier).to receive_messages(validate_url_for_ssrf!: true, configure_http_client: http)
  end

  def response(code, body = {})
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  it 'retries with a signed request when the server requires signed account fetches (401)' do
    create(:actor, local: true)
    allow(http).to receive(:request).and_return(response(401))
    allow(ActivityPubHttpClient).to receive(:fetch_verified)
      .with(actor_uri, signing_actor: kind_of(Actor)).and_return({ 'id' => actor_uri, 'type' => 'Person' })

    expect(verifier.send(:fetch_actor_data, actor_uri)).to include('id' => actor_uri)
  end

  it 'rejects an actor document whose id is on another host' do
    allow(http).to receive(:request).and_return(response(200, 'id' => 'https://attacker.example/users/a'))

    expect { verifier.send(:fetch_actor_data, actor_uri) }.to raise_error(ActivityPub::SignatureError)
  end

  it 'still reports the HTTP status when the actor is gone' do
    allow(http).to receive(:request).and_return(response(410))

    expect { verifier.send(:fetch_actor_data, actor_uri) }.to raise_error(ActivityPub::SignatureError, /HTTP 410/)
  end

  it 'treats a key that cannot be fetched as a failed verification, not as an error of this server' do
    allow(verifier).to receive_messages(parse_signature_header: { 'keyId' => "#{actor_uri}#main-key" },
                                        validate_date_header: true, verify_digest_header: true)
    allow(http).to receive(:request).and_return(response(404))
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)

    expect(verifier.verify!(actor_uri)).to be(false)
    expect(Rails.logger).to have_received(:warn).with(/HTTP 404/)
    expect(Rails.logger).not_to have_received(:error)
  end
end
