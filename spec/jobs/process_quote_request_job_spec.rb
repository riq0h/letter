# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessQuoteRequestJob do
  let(:owner) { create(:actor) }
  let(:quoted) { create(:activity_pub_object, actor: owner) }
  let(:requester) { create(:actor, :remote) }
  let(:quoting_uri) { "https://remote.example.com/users/#{requester.username}/statuses/1" }
  let(:sender) { instance_double(ActivitySender) }
  let(:sent) { [] }

  def quoting_note(quote: quoted.ap_id)
    { 'id' => quoting_uri, 'type' => 'Note', 'attributedTo' => requester.ap_id, 'content' => '<p>quoting</p>',
      'published' => Time.current.iso8601, 'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      'quote' => quote }.compact
  end

  def request(instrument: quoting_uri)
    { 'id' => "#{requester.ap_id}/quote_requests/1", 'type' => 'QuoteRequest',
      'actor' => requester.ap_id, 'object' => quoted.ap_id, 'instrument' => instrument }
  end

  before do
    allow(ActivitySender).to receive(:new).and_return(sender)
    allow(sender).to receive(:send_activity) { |**args| sent << args and { success: true, code: 202 } }
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with(quoting_uri, signing_actor: owner).and_return(quoting_note)
  end

  it 'accepts the request with an authorization the quoting server can verify' do
    described_class.perform_now(request, requester.id)

    expect(sent.size).to eq(1)
    payload = sent.first[:activity]
    expect(sent.first[:target_inbox]).to eq(requester.inbox_url)
    expect(payload).to include('type' => 'Accept', 'actor' => owner.ap_id)
    expect(payload['object']).to include('id' => request['id'], 'type' => 'QuoteRequest', 'instrument' => quoting_uri)

    authorization = QuoteAuthorization.find_by!(ap_id: payload['result'])
    expect(authorization.to_activitypub).to include('attributedTo' => owner.ap_id, 'interactingObject' => quoting_uri,
                                                    'interactionTarget' => quoted.ap_id)
  end

  it 'uses the quoting post embedded in the request when it cannot be fetched' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with(quoting_uri, signing_actor: owner).and_return(nil)

    described_class.perform_now(request(instrument: quoting_note), requester.id)

    expect(sent.first[:activity]['type']).to eq('Accept')
    expect(ActivityPubObject.find_by(ap_id: quoting_uri).actor).to eq(requester)
  end

  it 'rejects a request to quote a followers-only post' do
    quoted.update!(visibility: 'private')

    described_class.perform_now(request, requester.id)

    expect(sent.first[:activity]).to include('type' => 'Reject')
    expect(QuoteAuthorization.count).to eq(0)
  end

  it 'rejects a request from a blocked account' do
    Block.create!(actor: owner, target_actor: requester)

    described_class.perform_now(request, requester.id)

    expect(sent.first[:activity]).to include('type' => 'Reject')
  end

  it 'does not answer when the post does not actually quote the target' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with(quoting_uri, signing_actor: owner)
                                                            .and_return(quoting_note(quote: nil))

    described_class.perform_now(request, requester.id)

    expect(sent).to be_empty
  end

  it 'does not answer for a post that is not ours' do
    remote_post = create(:activity_pub_object, :remote, actor: create(:actor, :remote))

    described_class.perform_now(request.merge('object' => remote_post.ap_id), requester.id)

    expect(sent).to be_empty
  end
end
