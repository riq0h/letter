# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoteEmojiCopyService do
  describe '#cache_in_place' do
    let(:service) { described_class.new }

    it 'downloads and attaches the image to the remote emoji itself (no local copy)' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      allow(service).to receive(:download_image).with('https://remote.example.com/e.png')
                                                .and_return('dummy_image_data')

      result = service.cache_in_place(emoji)

      expect(result[:success]).to be true
      expect(emoji.reload.image.attached?).to be true
      # ローカルコピー(domain: nil)は作られない
      expect(CustomEmoji.local.count).to eq(0)
    end

    it 'stores the cached image under the cache/ folder (not emoji/)' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      allow(service).to receive(:download_image).and_return('dummy_image_data')

      expect(emoji).to receive(:attach_image_with_folder).with(hash_including(folder: 'cache'))
      service.cache_in_place(emoji)
    end

    it 'skips when already attached' do
      emoji = create(:custom_emoji, :remote)
      emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')

      expect(service).not_to receive(:download_image)
      expect(service.cache_in_place(emoji)[:success]).to be true
    end

    it 'refuses local emoji' do
      local = build(:custom_emoji, domain: nil, shortcode: 'smile')
      local.image.attach(io: StringIO.new('img'), filename: 'smile.png', content_type: 'image/png')
      local.save!
      expect(service.cache_in_place(local)[:success]).to be false
    end

    it 'returns failure (without raising) when download fails' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      allow(service).to receive(:download_image).and_raise(StandardError, 'boom')

      result = service.cache_in_place(emoji)

      expect(result[:success]).to be false
      expect(emoji.reload.image.attached?).to be false
    end
  end
end
