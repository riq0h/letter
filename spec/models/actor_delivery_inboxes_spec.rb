# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Actor do
  def remote_actor(name, domain, shared_inbox: nil)
    raw = { 'id' => "https://#{domain}/users/#{name}", 'inbox' => "https://#{domain}/users/#{name}/inbox" }
    raw['endpoints'] = { 'sharedInbox' => shared_inbox } if shared_inbox
    create(:actor, :remote, username: name, domain: domain, ap_id: raw['id'],
                            inbox_url: raw['inbox'], raw_data: raw.to_json)
  end

  describe 'shared_inbox_url column' do
    it 'is stored from endpoints.sharedInbox when raw_data is saved' do
      actor = remote_actor('alice', 'one.example', shared_inbox: 'https://one.example/inbox')

      expect(actor.read_attribute(:shared_inbox_url)).to eq('https://one.example/inbox')
    end
  end

  describe '.delivery_inboxes' do
    it 'collapses followers on the same server into its shared inbox' do
      a = remote_actor('alice', 'one.example', shared_inbox: 'https://one.example/inbox')
      b = remote_actor('bob', 'one.example', shared_inbox: 'https://one.example/inbox')
      c = remote_actor('carol', 'two.example')

      inboxes = described_class.delivery_inboxes(described_class.where(id: [a.id, b.id, c.id]))

      expect(inboxes).to contain_exactly('https://one.example/inbox', 'https://two.example/users/carol/inbox')
    end

    it 'falls back to raw_data for records whose column was never filled' do
      a = remote_actor('alice', 'one.example', shared_inbox: 'https://one.example/inbox')
      a.update_column(:shared_inbox_url, nil)

      expect(described_class.delivery_inboxes(described_class.where(id: a.id))).to eq(['https://one.example/inbox'])
    end
  end
end
