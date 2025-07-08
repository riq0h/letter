# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Content do
  describe '.parse' do
    it 'creates a Content object from text' do
      content = described_class.parse('Hello world!')
      expect(content.text).to eq('Hello world!')
    end

    it 'strips whitespace from text' do
      content = described_class.parse('  Hello world!  ')
      expect(content.text).to eq('Hello world!')
    end
  end

  describe '#initialize' do
    it 'extracts hashtags, mentions, and custom emojis' do
      text = 'Hello #world @alice@example.com!'
      content = described_class.new(text)

      expect(content.text).to eq(text)
      expect(content.hashtags).to include('world')
      expect(content.mentions).to include(hash_including(username: 'alice', domain: 'example.com'))
    end

    it 'handles empty text' do
      content = described_class.new('')
      expect(content.text).to eq('')
      expect(content.hashtags).to be_empty
      expect(content.mentions).to be_empty
    end

    it 'handles nil text' do
      content = described_class.new(nil)
      expect(content.text).to eq('')
    end
  end

  describe '#extract_hashtags' do
    it 'extracts hashtags correctly' do
      content = described_class.new('Hello #world #test #CASE')
      expect(content.hashtags).to contain_exactly('world', 'test', 'case')
    end

    it 'extracts Japanese hashtags' do
      content = described_class.new('こんにちは #日本語 #テスト')
      expect(content.hashtags).to contain_exactly('日本語', 'テスト')
    end

    it 'returns unique hashtags' do
      content = described_class.new('#test #Test #TEST')
      expect(content.hashtags).to eq(['test'])
    end

    it 'returns empty array when no hashtags' do
      content = described_class.new('Hello world')
      expect(content.hashtags).to be_empty
    end
  end

  describe '#extract_mentions' do
    it 'extracts local mentions' do
      content = described_class.new('Hello @alice and @bob')
      expect(content.mentions).to contain_exactly(
        hash_including(username: 'alice', domain: nil, acct: 'alice'),
        hash_including(username: 'bob', domain: nil, acct: 'bob')
      )
    end

    it 'extracts remote mentions' do
      content = described_class.new('Hello @alice@example.com and @bob@test.org')
      expect(content.mentions).to contain_exactly(
        hash_including(username: 'alice', domain: 'example.com', acct: 'alice@example.com'),
        hash_including(username: 'bob', domain: 'test.org', acct: 'bob@test.org')
      )
    end

    it 'returns unique mentions' do
      content = described_class.new('@alice @alice @alice@example.com')
      expect(content.mentions).to contain_exactly(
        hash_including(username: 'alice', domain: nil, acct: 'alice'),
        hash_including(username: 'alice', domain: 'example.com', acct: 'alice@example.com')
      )
    end

    it 'returns empty array when no mentions' do
      content = described_class.new('Hello world')
      expect(content.mentions).to be_empty
    end
  end

  describe '#empty?' do
    it 'returns true for empty text' do
      content = described_class.new('')
      expect(content).to be_empty
    end

    it 'returns true for whitespace-only text' do
      content = described_class.new('   ')
      expect(content).to be_empty
    end

    it 'returns false for non-empty text' do
      content = described_class.new('Hello')
      expect(content).not_to be_empty
    end
  end

  describe '#length' do
    it 'returns the length of the text' do
      content = described_class.new('Hello world!')
      expect(content.length).to eq(12)
    end

    it 'returns 0 for empty text' do
      content = described_class.new('')
      expect(content.length).to eq(0)
    end
  end

  describe '#hashtags?' do
    it 'returns true when hashtags are present' do
      content = described_class.new('Hello #world')
      expect(content).to be_hashtags
    end

    it 'returns false when no hashtags' do
      content = described_class.new('Hello world')
      expect(content).not_to be_hashtags
    end
  end

  describe '#mentions?' do
    it 'returns true when mentions are present' do
      content = described_class.new('Hello @alice')
      expect(content).to be_mentions
    end

    it 'returns false when no mentions' do
      content = described_class.new('Hello world')
      expect(content).not_to be_mentions
    end
  end

  describe '#custom_emojis?' do
    before do
      allow(CustomEmoji).to receive(:from_text).and_return({})
    end

    it 'returns true when custom emojis are present' do
      allow(CustomEmoji).to receive(:from_text).and_return({ smile: 'emoji_data' })
      content = described_class.new('Hello :smile:')
      expect(content).to be_custom_emojis
    end

    it 'returns false when no custom emojis' do
      content = described_class.new('Hello world')
      expect(content).not_to be_custom_emojis
    end
  end

  describe '#to_s' do
    it 'returns the text' do
      content = described_class.new('Hello world!')
      expect(content.to_s).to eq('Hello world!')
    end
  end

  describe '#==' do
    it 'returns true for same text content' do
      content1 = described_class.new('Hello world')
      content2 = described_class.new('Hello world')
      expect(content1).to eq(content2)
    end

    it 'returns false for different text content' do
      content1 = described_class.new('Hello world')
      content2 = described_class.new('Goodbye world')
      expect(content1).not_to eq(content2)
    end

    it 'returns false for objects of other classes' do
      content = described_class.new('Hello world')
      expect(content).not_to eq('Hello world')
    end
  end

  describe 'immutability' do
    it 'is immutable' do
      content = described_class.new('Hello world')
      expect(content).to be_frozen
    end
  end

  describe '#process_for_object' do
    let(:object) { double('object') } # rubocop:todo RSpec/VerifiedDoubles
    let(:object_tags) { double('object_tags') } # rubocop:todo RSpec/VerifiedDoubles
    let(:mentions) { double('mentions') } # rubocop:todo RSpec/VerifiedDoubles

    before do
      allow(object).to receive_messages(object_tags: object_tags, mentions: mentions)
      allow(object_tags).to receive(:find_or_create_by)
      allow(mentions).to receive(:find_or_create_by)
      allow(Tag).to receive(:find_or_create_by)
      allow(Actor).to receive(:find_by)
    end

    it 'creates hashtags and mentions for object' do
      content = described_class.new('Hello #world @alice')

      expect(Tag).to receive(:find_or_create_by).with(name: 'world') # rubocop:todo RSpec/MessageSpies
      expect(object_tags).to receive(:find_or_create_by) # rubocop:todo RSpec/MessageSpies

      content.process_for_object(object)
    end
  end
end
