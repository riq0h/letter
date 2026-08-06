# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackfillRepliesJob do
  let(:remote_actor) { create(:actor, :remote) }

  def remote_note(ap_id, raw)
    create(:activity_pub_object, :note, actor: remote_actor, local: false,
                                        ap_id: ap_id, visibility: 'public', raw_data: raw.to_json)
  end

  it 'prefers the FEP-7888 context collection and resolves unknown members' do
    target = remote_note('https://remote.example.com/notes/1',
                         context: 'https://remote.example.com/contexts/abc',
                         replies: 'https://remote.example.com/notes/1/replies')
    collection = {
      'type' => 'OrderedCollection',
      'orderedItems' => [
        'https://remote.example.com/notes/1', # 既知 → スキップ
        'https://remote.example.com/notes/2',
        'https://remote.example.com/notes/3'
      ]
    }
    allow(ActivityPubHttpClient).to receive(:fetch_object)
      .with('https://remote.example.com/contexts/abc').and_return(collection)
    resolver = instance_double(Search::RemoteResolverService)
    allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:resolve_remote_status).and_return(nil)

    described_class.perform_now(target.id)

    expect(resolver).to have_received(:resolve_remote_status).with('https://remote.example.com/notes/2')
    expect(resolver).to have_received(:resolve_remote_status).with('https://remote.example.com/notes/3')
    expect(resolver).not_to have_received(:resolve_remote_status).with('https://remote.example.com/notes/1')
  end

  it 'falls back to the replies collection (inline first page) when no context exists' do
    target = remote_note('https://remote.example.com/notes/10',
                         replies: {
                           'type' => 'Collection',
                           'first' => { 'type' => 'CollectionPage',
                                        'items' => ['https://remote.example.com/notes/11'] }
                         })
    resolver = instance_double(Search::RemoteResolverService)
    allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:resolve_remote_status).and_return(nil)

    described_class.perform_now(target.id)

    expect(resolver).to have_received(:resolve_remote_status).with('https://remote.example.com/notes/11')
  end

  it 'does nothing for local statuses' do
    local = create(:activity_pub_object, :note, actor: create(:actor, local: true))
    allow(ActivityPubHttpClient).to receive(:fetch_object)

    described_class.perform_now(local.id)

    expect(ActivityPubHttpClient).not_to have_received(:fetch_object)
  end

  describe '#quick_pass (同期クイックパス)' do
    it 'resolves unknown replies within the deadline and returns the created count' do
      target = remote_note('https://remote.example.com/notes/30',
                           context: 'https://remote.example.com/contexts/q')
      collection = { 'type' => 'OrderedCollection',
                     'orderedItems' => ['https://remote.example.com/notes/30',
                                        'https://remote.example.com/notes/31'] }
      reply_json = { 'id' => 'https://remote.example.com/notes/31', 'type' => 'Note' }
      allow(ActivityPubHttpClient).to receive(:fetch_object)
        .with('https://remote.example.com/contexts/q', timeout: 4).and_return(collection)
      allow(ActivityPubHttpClient).to receive(:fetch_object)
        .with('https://remote.example.com/notes/31', timeout: 4).and_return(reply_json)
      resolver = Search::RemoteResolverService.new
      allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:create_remote_object).with(reply_json)
                                                       .and_return(instance_double(ActivityPubObject))

      created = described_class.new.quick_pass(target, deadline: 5.seconds.from_now)

      expect(created).to eq(1)
    end

    it 'creates nothing when the deadline has already passed' do
      target = remote_note('https://remote.example.com/notes/40',
                           context: 'https://remote.example.com/contexts/late')
      collection = { 'type' => 'OrderedCollection',
                     'orderedItems' => ['https://remote.example.com/notes/41'] }
      allow(ActivityPubHttpClient).to receive(:fetch_object).and_return(collection)
      resolver = Search::RemoteResolverService.new
      allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:create_remote_object)

      created = described_class.new.quick_pass(target, deadline: 1.second.ago)

      expect(created).to eq(0)
      expect(resolver).not_to have_received(:create_remote_object)
    end
  end

  it 'stops resolving once the item budget is exhausted' do
    items = (1..60).map { |i| "https://remote.example.com/notes/x#{i}" }
    target = remote_note('https://remote.example.com/notes/20',
                         context: 'https://remote.example.com/contexts/big')
    allow(ActivityPubHttpClient).to receive(:fetch_object)
      .and_return({ 'type' => 'OrderedCollection', 'orderedItems' => items })
    resolver = instance_double(Search::RemoteResolverService)
    allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)
    allow(resolver).to receive(:resolve_remote_status) { instance_double(ActivityPubObject, raw_data: '{}') }

    described_class.perform_now(target.id)

    expect(resolver).to have_received(:resolve_remote_status).exactly(described_class::MAX_ITEMS).times
  end
end
