# frozen_string_literal: true

require 'rails_helper'

# 購読しているリレーから届く活動。リレーは共有inboxにも個人のinboxにも送ってくる
RSpec.describe 'Activities from a subscribed relay', type: :request do
  include ActiveJob::TestHelper

  let(:relay_actor_uri) { 'https://relay.example.com/actor' }
  let(:follow_id) { 'https://test.example.com/users/admin#follows/relay/0123' }
  let!(:relay) do
    create(:relay, :pending, inbox_url: 'https://relay.example.com/inbox', follow_activity_id: follow_id)
  end
  let!(:local_actor) { create(:actor) }
  let(:author) { create(:actor, :remote, domain: 'origin.example', ap_id: 'https://origin.example/users/alice') }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{relay_actor_uri}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end

  before do
    create(:actor, :remote, domain: 'relay.example.com', ap_id: relay_actor_uri)
    allow(HttpSignatureVerifier).to receive(:new).and_return(verifier)
  end

  def activity(type, object, actor: relay_actor_uri)
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{actor}/activities/#{SecureRandom.hex(4)}",
      'type' => type, 'actor' => actor, 'object' => object }.to_json
  end

  def embedded_follow
    { 'id' => follow_id, 'type' => 'Follow', 'actor' => local_actor.ap_id,
      'object' => 'https://www.w3.org/ns/activitystreams#Public' }
  end

  %w[/inbox personal].each do |inbox|
    context "when delivered to #{inbox == '/inbox' ? 'the shared inbox' : 'the personal inbox'}" do
      let(:path) { inbox == '/inbox' ? '/inbox' : "/users/#{local_actor.username}/inbox" }

      it 'starts the subscription when the relay accepts the Follow it embeds' do
        post path, params: activity('Accept', embedded_follow), headers: headers

        expect(response).to have_http_status(:accepted)
        expect(relay.reload).to be_accepted
      end

      it 'records a rejection' do
        post path, params: activity('Reject', follow_id), headers: headers

        expect(relay.reload).to be_rejected
        expect(relay.follow_activity_id).to be_nil
      end

      it 'fetches a relayed post from its origin instead of trusting the relay' do
        expect do
          post path, params: activity('Announce', 'https://origin.example/notes/1'), headers: headers
        end.to have_enqueued_job(FetchForwardedObjectJob).with('https://origin.example/notes/1', nil, relay.id)

        expect(relay.reload).to be_accepted
      end

      it 'treats a post the relay passes on for its author like a forwarded one' do
        note = { 'id' => 'https://origin.example/notes/2', 'type' => 'Note', 'attributedTo' => author.ap_id,
                 'content' => '<p>written by the relay</p>', 'to' => ['https://www.w3.org/ns/activitystreams#Public'] }

        expect do
          post path, params: activity('Create', note, actor: author.ap_id), headers: headers
        end.to have_enqueued_job(FetchForwardedObjectJob).with(note['id'], author.ap_id, relay.id)

        expect(ActivityPubObject.exists?(ap_id: note['id'])).to be(false)
      end

      it 'imports the post a relayed boost points to, without recording the boost itself' do
        booster = create(:actor, :remote, domain: 'other.example', ap_id: 'https://other.example/users/bob')

        expect do
          post path, params: activity('Announce', 'https://origin.example/notes/4', actor: booster.ap_id), headers: headers
        end.to have_enqueued_job(FetchForwardedObjectJob).with('https://origin.example/notes/4', nil, relay.id)

        expect(Reblog.where(actor: booster)).to be_empty
      end

      it 'does not let the relay delete a post in the name of its author' do
        status = create(:activity_pub_object, :remote, actor: author, ap_id: 'https://origin.example/notes/3')

        post path, params: activity('Delete', status.ap_id, actor: author.ap_id), headers: headers

        expect(response).to have_http_status(:accepted)
        expect(ActivityPubObject.exists?(status.id)).to be(true)
      end
    end
  end
end
