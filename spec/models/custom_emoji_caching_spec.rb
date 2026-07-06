# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomEmoji do
  include ActiveJob::TestHelper

  describe '#url' do
    it 'serves a remote emoji from the local attachment (R2) once cached' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')

      expect(emoji.image.attached?).to be true
      expect(emoji.url).to be_present
      expect(emoji.url).not_to eq('https://remote.example.com/e.png')
    end

    it 'is pure (no job enqueued) so validation/serialization side effects are avoided' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')

      expect(CacheRemoteEmojiJob).not_to receive(:perform_later)
      expect(emoji.url).to eq('https://remote.example.com/e.png')
    end
  end

  describe '#to_activitypub (display path) triggers caching' do
    it 'enqueues caching for an uncached remote emoji' do
      allow(Rails.cache).to receive(:write).and_return(true)
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')

      expect(CacheRemoteEmojiJob).to receive(:perform_later).with(emoji.id)
      emoji.to_activitypub
    end

    it 'enqueues only once per emoji instance' do
      allow(Rails.cache).to receive(:write).and_return(true)
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')

      expect(CacheRemoteEmojiJob).to receive(:perform_later).once
      emoji.to_activitypub
      emoji.to_activitypub
    end

    it 'does not enqueue for an already-cached remote emoji' do
      emoji = create(:custom_emoji, :remote, image_url: 'https://remote.example.com/e.png')
      emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')

      expect(CacheRemoteEmojiJob).not_to receive(:perform_later)
      emoji.to_activitypub
    end
  end

  describe 'emoji rendering adds referrerpolicy to avoid remote hotlink protection' do
    # 直リンク経路(未キャッシュのリモート絵文字)を検証するため remote 絵文字を使う
    let(:emoji) { create(:custom_emoji, :remote, shortcode: 'smile') }

    it 'EmojiPresenter renders custom emoji img with referrerpolicy=no-referrer' do
      emoji
      html = EmojiPresenter.present_with_emojis(':smile:')
      expect(html).to include('referrerpolicy="no-referrer"')
    end

    it 'EmojiFormatter renders custom emoji img with referrerpolicy' do
      html = EmojiFormatter.emojify(':smile:', custom_emojis: { 'smile' => emoji })
      expect(html).to include('referrerpolicy')
    end
  end
end
