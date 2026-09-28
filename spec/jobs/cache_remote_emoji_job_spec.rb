# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CacheRemoteEmojiJob do
  it 'caches an uncached remote emoji in place' do
    emoji = create(:custom_emoji, :remote)
    service = instance_double(RemoteEmojiCopyService)
    allow(RemoteEmojiCopyService).to receive(:new).and_return(service)

    expect(service).to receive(:cache_in_place).with(emoji)

    described_class.perform_now(emoji.id)
  end

  it 'does nothing for a local emoji' do
    local = build(:custom_emoji, domain: nil, shortcode: 'smile')
    local.image.attach(io: StringIO.new('img'), filename: 'smile.png', content_type: 'image/png')
    local.save!
    allow(RemoteEmojiCopyService).to receive(:new)

    described_class.perform_now(local.id)

    expect(RemoteEmojiCopyService).not_to have_received(:new)
  end

  it 'does nothing when already cached' do
    emoji = create(:custom_emoji, :remote)
    emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')
    allow(RemoteEmojiCopyService).to receive(:new)

    described_class.perform_now(emoji.id)

    expect(RemoteEmojiCopyService).not_to have_received(:new)
  end

  it 'does nothing when the emoji is missing' do
    allow(RemoteEmojiCopyService).to receive(:new)

    described_class.perform_now(-1)

    expect(RemoteEmojiCopyService).not_to have_received(:new)
  end

  describe 'when the remote image is gone (emoji replaced on the origin)' do
    # 相手サーバで絵文字が差し替えられ、プロフィール上の絵文字の旧URLが404になるケース。
    # MastodonはUpdate(Person)を送らないため、プロフィール所有者の再取得で新URLを得る
    let(:emoji) { create(:custom_emoji, :remote, shortcode: 'mastodon', domain: 'origin.example') }
    let(:service) { instance_double(RemoteEmojiCopyService) }
    let!(:owner) { create(:actor, :remote, domain: 'origin.example', display_name: 'alice :mastodon:') }

    before do
      allow(RemoteEmojiCopyService).to receive(:new).and_return(service)
      create(:actor, :remote, domain: 'other.example', display_name: 'x :mastodon:')
    end

    it 'refreshes actors on the same domain whose profile uses the emoji' do
      allow(service).to receive(:cache_in_place)
        .and_return({ success: false, error: '画像のダウンロードに失敗しました: Failed to download image: HTTP 404' })

      expect { described_class.perform_now(emoji.id) }
        .to have_enqueued_job(RefreshRemoteActorJob).with(owner.id).exactly(:once)
    end

    it 'matches shortcodes containing underscores literally' do
      underscored = create(:custom_emoji, :remote, shortcode: 'blobcat_dancing', domain: 'origin.example')
      dancer = create(:actor, :remote, domain: 'origin.example', display_name: ':blobcat_dancing:bob')
      allow(service).to receive(:cache_in_place).and_return({ success: false, error: 'HTTP 410' })

      expect { described_class.perform_now(underscored.id) }
        .to have_enqueued_job(RefreshRemoteActorJob).with(dancer.id)
    end

    it 'does not refresh on transient failures' do
      allow(service).to receive(:cache_in_place).and_return({ success: false, error: 'database is locked' })

      expect { described_class.perform_now(emoji.id) }.not_to have_enqueued_job(RefreshRemoteActorJob)
    end
  end
end
