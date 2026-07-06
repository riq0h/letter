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
end
