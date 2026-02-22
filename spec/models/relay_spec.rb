# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Relay, type: :model do
  describe 'validations' do
    it 'requires inbox_url' do
      relay = build(:relay, inbox_url: nil)
      expect(relay).not_to be_valid
    end

    it 'requires unique inbox_url' do
      create(:relay, inbox_url: 'https://relay.example.com/inbox')
      relay = build(:relay, inbox_url: 'https://relay.example.com/inbox')
      expect(relay).not_to be_valid
    end
  end

  describe '#normalize_inbox_url' do
    it 'appends /inbox if missing' do
      relay = create(:relay, inbox_url: 'https://relay.example.com')
      expect(relay.inbox_url).to eq('https://relay.example.com/inbox')
    end

    it 'does not duplicate /inbox' do
      relay = create(:relay, inbox_url: 'https://relay.example.com/inbox')
      expect(relay.inbox_url).to eq('https://relay.example.com/inbox')
    end

    it 'strips whitespace' do
      relay = create(:relay, inbox_url: '  https://relay.example.com/inbox  ')
      expect(relay.inbox_url).to eq('https://relay.example.com/inbox')
    end
  end

  describe '#actor_uri' do
    it 'returns DB value when stored' do
      relay = create(:relay, actor_uri: 'https://relay.example.com/custom-actor')
      expect(relay.actor_uri).to eq('https://relay.example.com/custom-actor')
    end

    it 'derives from inbox_url when DB value is nil' do
      relay = create(:relay, inbox_url: 'https://relay.example.com/inbox', actor_uri: nil)
      expect(relay.actor_uri).to eq('https://relay.example.com/actor')
    end

    it 'derives from inbox_url when DB value is empty string' do
      relay = create(:relay, inbox_url: 'https://relay.example.com/inbox')
      relay.update_column(:actor_uri, '')
      expect(relay.actor_uri).to eq('https://relay.example.com/actor')
    end

    it 'includes non-default port in derived URI' do
      relay = create(:relay, inbox_url: 'https://relay.example.com:8443/inbox', actor_uri: nil)
      expect(relay.actor_uri).to eq('https://relay.example.com:8443/actor')
    end
  end

  describe '#domain' do
    it 'extracts domain from inbox_url' do
      relay = create(:relay, inbox_url: 'https://relay.example.com/inbox')
      expect(relay.domain).to eq('relay.example.com')
    end
  end

  describe 'state predicates' do
    it '#idle? returns true for idle state' do
      expect(build(:relay, state: 'idle')).to be_idle
    end

    it '#pending? returns true for pending state' do
      expect(build(:relay, state: 'pending')).to be_pending
    end

    it '#accepted? returns true for accepted state' do
      expect(build(:relay, state: 'accepted')).to be_accepted
    end

    it '#rejected? returns true for rejected state' do
      expect(build(:relay, state: 'rejected')).to be_rejected
    end
  end

  describe 'before_destroy :ensure_disabled' do
    it 'calls RelayUnfollowService when accepted' do
      relay = create(:relay, :accepted)
      service = instance_double(RelayUnfollowService)
      allow(RelayUnfollowService).to receive(:new).and_return(service)
      allow(service).to receive(:call)

      relay.destroy

      expect(service).to have_received(:call).with(relay)
    end

    it 'does not call RelayUnfollowService when idle' do
      relay = create(:relay, state: 'idle')
      allow(RelayUnfollowService).to receive(:new)

      relay.destroy

      expect(RelayUnfollowService).not_to have_received(:new)
    end
  end

  describe 'scopes' do
    it '.enabled returns only accepted relays' do
      create(:relay, state: 'idle')
      create(:relay, :rejected)
      accepted = create(:relay, :accepted)

      expect(described_class.enabled).to contain_exactly(accepted)
    end

    it '.pending returns only pending relays' do
      create(:relay, state: 'idle')
      pending_relay = create(:relay, :pending)

      expect(described_class.pending).to contain_exactly(pending_relay)
    end
  end
end
