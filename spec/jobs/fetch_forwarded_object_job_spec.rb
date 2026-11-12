# frozen_string_literal: true

require 'rails_helper'

# 転送されたCreateは本文を使わず、元のサーバから取り直して取り込む
RSpec.describe FetchForwardedObjectJob do
  let!(:author) { create(:actor, :remote, domain: 'origin.example', ap_id: 'https://origin.example/users/alice') }
  let(:object_uri) { 'https://origin.example/notes/1' }

  def original(author_uri: author.ap_id, id: object_uri)
    { 'id' => id, 'type' => 'Note', 'attributedTo' => author_uri, 'content' => '<p>original</p>',
      'published' => Time.current.iso8601, 'to' => ['https://www.w3.org/ns/activitystreams#Public'] }
  end

  it 'imports the copy fetched from the origin, attributed to its real author' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified).with(object_uri).and_return(original)

    described_class.perform_now(object_uri, author.ap_id)

    stored = ActivityPubObject.find_by(ap_id: object_uri)
    expect(stored.actor).to eq(author)
    expect(stored.content).to include('original')
  end

  it 'does nothing when the origin says the author is someone else' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified)
      .and_return(original(author_uri: 'https://origin.example/users/bob'))

    described_class.perform_now(object_uri, author.ap_id)

    expect(ActivityPubObject.exists?(ap_id: object_uri)).to be false
  end

  it 'does not even fetch when the object is not on the claimed author host' do
    allow(ActivityPubHttpClient).to receive(:fetch_verified)

    described_class.perform_now('https://attacker.example/notes/1', author.ap_id)

    expect(ActivityPubHttpClient).not_to have_received(:fetch_verified)
  end
end
