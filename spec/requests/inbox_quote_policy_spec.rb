# frozen_string_literal: true

require 'rails_helper'

# 承認を求めずに届く引用(Misskeyなど)も、投稿の引用の許可設定に従って記録する
RSpec.describe 'Quotes of our posts arriving without a quote request', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:local_actor) { create(:actor) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end
  let(:public_collection) { 'https://www.w3.org/ns/activitystreams#Public' }

  def deliver_quote_of(quoted)
    note = { 'id' => "#{remote.ap_id}/notes/1", 'type' => 'Note', 'attributedTo' => remote.ap_id,
             'content' => '<p>これいいね</p>', 'published' => Time.current.iso8601,
             'to' => [public_collection], '_misskey_quote' => quoted.ap_id }
    create = { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}/notes/1/activity",
               'type' => 'Create', 'actor' => remote.ap_id, 'object' => note, 'to' => [public_collection] }
    post "/users/#{local_actor.username}/inbox", params: create.to_json, headers: headers
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  it 'records the quote of a post anyone may quote' do
    quoted = create(:activity_pub_object, actor: local_actor)

    expect { deliver_quote_of(quoted) }.to change(QuotePost, :count).by(1)
  end

  it 'does not record the quote of a post nobody else may quote' do
    quoted = create(:activity_pub_object, actor: local_actor, quote_policy: 'nobody')

    expect { deliver_quote_of(quoted) }.not_to change(QuotePost, :count)
    expect(ActivityPubObject.find_by(ap_id: "#{remote.ap_id}/notes/1")).to be_present
  end
end
