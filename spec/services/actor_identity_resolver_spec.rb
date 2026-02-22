# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActorIdentityResolver do
  let(:test_class) do
    Class.new do
      include ActorIdentityResolver
    end
  end
  let(:resolver) { test_class.new }

  let(:public_key) { OpenSSL::PKey::RSA.new(2048).public_key.to_pem }

  describe '#resolve_actor_identity_conflict' do
    let!(:existing_actor) do
      create(:actor, :remote,
             username: 'alice',
             domain: 'example.com',
             ap_id: 'https://example.com/users/alice-old',
             inbox_url: 'https://example.com/users/alice-old/inbox',
             outbox_url: 'https://example.com/users/alice-old/outbox',
             display_name: 'Old Alice')
    end

    let(:new_ap_id) { 'https://example.com/users/alice-new' }
    let(:new_attrs) do
      {
        username: 'alice',
        domain: 'example.com',
        display_name: 'New Alice',
        inbox_url: 'https://example.com/users/alice-new/inbox',
        outbox_url: 'https://example.com/users/alice-new/outbox',
        public_key: public_key,
        local: false
      }
    end

    it 'updates existing actor when username@domain matches but ap_id differs' do
      result = resolver.resolve_actor_identity_conflict(new_ap_id, 'alice', 'example.com', new_attrs)

      expect(result).to eq(existing_actor)
      expect(result.ap_id).to eq(new_ap_id)
      expect(result.display_name).to eq('New Alice')
      expect(result.inbox_url).to eq('https://example.com/users/alice-new/inbox')
    end

    it 'returns nil when no existing actor with same username@domain' do
      result = resolver.resolve_actor_identity_conflict(new_ap_id, 'bob', 'example.com', new_attrs)

      expect(result).to be_nil
    end

    it 'returns nil when ap_id is the same (not a conflict)' do
      result = resolver.resolve_actor_identity_conflict(existing_actor.ap_id, 'alice', 'example.com', new_attrs)

      expect(result).to be_nil
      existing_actor.reload
      expect(existing_actor.display_name).to eq('Old Alice')
    end
  end

  describe 'integration with ActorFetcher' do
    let(:fetcher) { ActorFetcher.new }

    let!(:existing_actor) do
      create(:actor, :remote,
             username: 'alice',
             domain: 'example.com',
             ap_id: 'https://example.com/users/alice-old',
             inbox_url: 'https://example.com/users/alice-old/inbox',
             outbox_url: 'https://example.com/users/alice-old/outbox')
    end

    let(:new_ap_id) { 'https://example.com/users/alice-new' }
    let(:actor_data) do
      {
        'id' => new_ap_id,
        'type' => 'Person',
        'preferredUsername' => 'alice',
        'name' => 'New Alice',
        'inbox' => 'https://example.com/users/alice-new/inbox',
        'outbox' => 'https://example.com/users/alice-new/outbox',
        'followers' => 'https://example.com/users/alice-new/followers',
        'following' => 'https://example.com/users/alice-new/following',
        'publicKey' => { 'publicKeyPem' => public_key }
      }
    end

    it 'resolves identity conflict via ActorFetcher#create_actor_from_data' do
      result = fetcher.create_actor_from_data(new_ap_id, actor_data)

      expect(result.id).to eq(existing_actor.id)
      expect(result.ap_id).to eq(new_ap_id)
      expect(Actor.where(username: 'alice', domain: 'example.com').count).to eq(1)
    end
  end

  describe 'integration with ActorCreationService' do
    let(:service) { ActorCreationService.new }

    let!(:existing_actor) do
      create(:actor, :remote,
             username: 'bob',
             domain: 'remote.example.com',
             ap_id: 'https://remote.example.com/users/bob-old',
             inbox_url: 'https://remote.example.com/users/bob-old/inbox',
             outbox_url: 'https://remote.example.com/users/bob-old/outbox')
    end

    let(:new_ap_id) { 'https://remote.example.com/users/bob-new' }
    let(:actor_data) do
      {
        'id' => new_ap_id,
        'type' => 'Person',
        'preferredUsername' => 'bob',
        'name' => 'New Bob',
        'inbox' => 'https://remote.example.com/users/bob-new/inbox',
        'outbox' => 'https://remote.example.com/users/bob-new/outbox',
        'followers' => 'https://remote.example.com/users/bob-new/followers',
        'following' => 'https://remote.example.com/users/bob-new/following',
        'publicKey' => { 'publicKeyPem' => public_key }
      }
    end

    it 'resolves identity conflict via ActorCreationService' do
      result = service.create_from_activitypub_data(actor_data)

      expect(result.id).to eq(existing_actor.id)
      expect(result.ap_id).to eq(new_ap_id)
      expect(result.display_name).to eq('New Bob')
      expect(Actor.where(username: 'bob', domain: 'remote.example.com').count).to eq(1)
    end

    it 'creates a new actor when no conflict exists' do
      actor_data['preferredUsername'] = 'charlie'
      actor_data['id'] = 'https://remote.example.com/users/charlie'

      expect { service.create_from_activitypub_data(actor_data) }.to change(Actor, :count).by(1)
    end
  end
end
