# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActorFetcher do
  describe '#refresh' do
    let(:fetcher) { described_class.new }
    let(:actor) do
      create(:actor, :remote, ap_id: 'https://remote.example.com/users/bob',
                              display_name: 'Old Name', raw_data: '{}')
    end

    let(:actor_data) do
      {
        'id' => actor.ap_id,
        'type' => 'Person',
        'preferredUsername' => actor.username,
        'name' => 'New Name',
        'inbox' => 'https://remote.example.com/inbox',
        'outbox' => 'https://remote.example.com/outbox',
        'publicKey' => { 'publicKeyPem' => 'PEM' },
        'icon' => { 'type' => 'Image', 'url' => 'https://remote.example.com/new-avatar.png' }
      }
    end

    before do
      # テスト用ドメインは名前解決できずSSRFチェックで弾かれるため無効化
      allow(fetcher).to receive(:validate_url_for_ssrf!).and_return(true)
      allow(ActivityPubHttpClient).to receive(:fetch_object).with(actor.ap_id).and_return(actor_data)
      # 画像の実ダウンロードは行わない
      allow(fetcher).to receive(:reattach_remote_images)
    end

    it 'updates profile data and raw_data from the refetched document' do
      fetcher.refresh(actor)
      actor.reload

      expect(actor.display_name).to eq('New Name')
      expect(JSON.parse(actor.raw_data).dig('icon', 'url')).to eq('https://remote.example.com/new-avatar.png')
    end

    it 're-attaches remote images using the fresh data' do
      expect(fetcher).to receive(:reattach_remote_images).with(actor, actor_data)
      fetcher.refresh(actor)
    end

    it 'does not change identity fields (ap_id/username/domain)' do
      expect { fetcher.refresh(actor) }.not_to(change { actor.reload.slice('ap_id', 'username', 'domain') })
    end

    it 'returns nil without raising when the fetch fails' do
      allow(ActivityPubHttpClient).to receive(:fetch_object).and_return(nil)

      expect { fetcher.refresh(actor) }.not_to raise_error
      expect(fetcher.refresh(actor)).to be_nil
    end

    it 'ignores local actors' do
      local = create(:actor, local: true)
      expect(fetcher.refresh(local)).to be_nil
    end
  end
end
