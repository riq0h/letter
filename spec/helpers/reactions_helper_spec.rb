# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactionsHelper do
  let(:reactor) { create(:actor, :remote, domain: 'misskey.example.com') }
  let(:status) { create(:activity_pub_object, actor: create(:actor, local: true)) }
  let(:favourites) { [create(:favourite, actor: reactor, object: status, reaction: ':igyo:')] }

  describe '#reaction_custom_emoji' do
    it 'resolves the emoji by the reactor domain first' do
      create(:custom_emoji, :remote, shortcode: 'igyo', domain: 'other.example.com',
                                     image_url: 'https://other.example.com/e.png')
      target = create(:custom_emoji, :remote, shortcode: 'igyo', domain: 'misskey.example.com',
                                              image_url: 'https://misskey.example.com/e.png')

      expect(helper.reaction_custom_emoji(':igyo:', favourites)).to eq(target)
    end

    it 'falls back to any domain when the reactor domain has no record' do
      other = create(:custom_emoji, :remote, shortcode: 'igyo', domain: 'other.example.com',
                                             image_url: 'https://other.example.com/e.png')

      expect(helper.reaction_custom_emoji(':igyo:', favourites)).to eq(other)
    end

    it 'returns nil for a unicode emoji reaction' do
      expect(helper.reaction_custom_emoji('👍', favourites)).to be_nil
    end

    it 'returns nil when no record exists' do
      expect(helper.reaction_custom_emoji(':unknown:', favourites)).to be_nil
    end

    it 'requests R2 caching when the resolved emoji is not cached yet (display trigger)' do
      allow(Rails.cache).to receive(:write).and_return(true)
      emoji = create(:custom_emoji, :remote, shortcode: 'igyo', domain: 'misskey.example.com',
                                             image_url: 'https://misskey.example.com/e.png')

      expect(CacheRemoteEmojiJob).to receive(:perform_later).with(emoji.id)
      helper.reaction_custom_emoji(':igyo:', favourites)
    end

    it 'does not request caching when the emoji is already cached' do
      emoji = create(:custom_emoji, :remote, shortcode: 'igyo', domain: 'misskey.example.com',
                                             image_url: 'https://misskey.example.com/e.png')
      emoji.image.attach(io: StringIO.new('img'), filename: 'e.png', content_type: 'image/png')

      expect(CacheRemoteEmojiJob).not_to receive(:perform_later)
      helper.reaction_custom_emoji(':igyo:', favourites)
    end
  end

  describe '#reaction_display_text' do
    it 'converts legacy Misskey named reactions to unicode emoji (stored rows rescue)' do
      expect(helper.reaction_display_text('star')).to eq('⭐')
    end

    it 'passes through unicode emoji and unknown values unchanged' do
      expect(helper.reaction_display_text('👍')).to eq('👍')
      expect(helper.reaction_display_text(':unknown:')).to eq(':unknown:')
    end
  end

  describe '#reaction_title' do
    it 'lists reactor handles' do
      title = helper.reaction_title(':igyo:', favourites)
      expect(title).to include(':igyo:')
      expect(title).to include(reactor.username)
    end

    it 'truncates beyond 10 reactors' do
      favs = Array.new(12) do |i|
        create(:favourite, actor: create(:actor, :remote, domain: 'misskey.example.com'),
                           object: status, reaction: '👍', ap_id: "https://misskey.example.com/likes/#{i}")
      end

      expect(helper.reaction_title('👍', favs)).to include('他2人')
    end
  end
end
