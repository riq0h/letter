# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmojiPresenter do
  describe '#extract_shortcodes' do
    it 'extracts unique shortcodes from text' do
      text = 'Hello :smile: and :heart: and :smile: again!'
      presenter = described_class.new(text)

      result = presenter.extract_shortcodes

      expect(result).to contain_exactly('smile', 'heart')
    end

    it 'returns empty array for text without shortcodes' do
      text = 'Hello world!'
      presenter = described_class.new(text)

      result = presenter.extract_shortcodes

      expect(result).to be_empty
    end
  end

  describe '#to_html with mocked emoji' do
    let(:mock_emoji) do
      instance_double(CustomEmoji,
                      shortcode: 'smile',
                      image_url: 'https://example.com/emoji/smile.png')
    end

    before do
      allow_any_instance_of(described_class).to receive(:find_emoji)
        .with('smile').and_return(mock_emoji)
      allow_any_instance_of(described_class).to receive(:find_emoji)
        .with('unknown').and_return(nil)
    end

    it 'converts emoji shortcodes to HTML' do
      text = 'Hello :smile: world!'
      presenter = described_class.new(text)

      result = presenter.to_html

      expect(result).to include('<img')
      expect(result).to include('custom-emoji')
      expect(result).to include(':smile:')
      expect(result).to include('https://example.com/emoji/smile.png')
    end

    it 'preserves text without emoji shortcodes' do
      text = 'Hello world!'
      presenter = described_class.new(text)

      result = presenter.to_html

      expect(result).to eq('Hello world!')
    end

    it 'handles unknown emoji shortcodes' do
      text = 'Hello :unknown: world!'
      presenter = described_class.new(text)

      result = presenter.to_html

      expect(result).to eq('Hello :unknown: world!')
    end
  end

  describe '#used_emojis with mocked data' do
    let(:mock_emoji) do
      instance_double(CustomEmoji, shortcode: 'smile')
    end

    before do
      local_scope = instance_double(ActiveRecord::Relation)
      remote_scope = instance_double(ActiveRecord::Relation)

      allow(local_scope).to receive(:where).and_return([mock_emoji])
      allow(CustomEmoji).to receive_messages(enabled: CustomEmoji, visible: local_scope, remote: remote_scope)
      allow(remote_scope).to receive(:where).and_return([])
    end

    it 'returns emoji objects for shortcodes in text' do
      text = 'Hello :smile: world!'
      presenter = described_class.new(text)

      result = presenter.used_emojis

      expect(result).to include(mock_emoji)
    end
  end

  describe '.present_with_emojis' do
    before do
      allow_any_instance_of(described_class).to receive(:to_html)
        .and_return('Hello <img>emoji</img> world!')
    end

    it 'converts emojis to HTML using class method' do
      text = 'Hello :smile: world!'

      result = described_class.present_with_emojis(text)

      expect(result).to eq('Hello <img>emoji</img> world!')
    end
  end

  describe '.extract_emojis_from' do
    before do
      allow_any_instance_of(described_class).to receive(:used_emojis)
        .and_return(['mock_emoji'])
    end

    it 'extracts emoji objects using class method' do
      text = 'Hello :smile: world!'

      result = described_class.extract_emojis_from(text)

      expect(result).to eq(['mock_emoji'])
    end
  end

  describe '.extract_shortcodes_from' do
    it 'extracts shortcodes using class method' do
      text = 'Hello :smile: and :heart: world!'

      result = described_class.extract_shortcodes_from(text)

      expect(result).to contain_exactly('smile', 'heart')
    end
  end

  describe 'HTML generation' do
    let(:mock_emoji) do
      instance_double(CustomEmoji,
                      shortcode: 'smile',
                      image_url: 'https://example.com/emoji/smile.png')
    end

    before do
      allow_any_instance_of(described_class).to receive(:find_emoji)
        .and_return(mock_emoji)
    end

    it 'generates proper HTML attributes' do
      text = 'Hello :smile: world!'
      presenter = described_class.new(text)

      result = presenter.to_html

      expect(result).to include('class="custom-emoji"')
      expect(result).to include('alt=":smile:"')
      expect(result).to include('title=":smile:"')
      expect(result).to include('draggable="false"')
      expect(result).to include('style=')
    end

    it 'includes proper CSS styling' do
      text = 'Hello :smile: world!'
      presenter = described_class.new(text)

      result = presenter.to_html

      expect(result).to include('width: 1.2em')
      expect(result).to include('height: 1.2em')
      expect(result).to include('display: inline-block')
      expect(result).to include('vertical-align: text-bottom')
      expect(result).to include('object-fit: contain')
    end
  end

  describe 'empty or blank text' do
    it 'handles empty string' do
      presenter = described_class.new('')

      result = presenter.to_html

      expect(result).to eq('')
    end

    it 'handles nil text' do
      presenter = described_class.new(nil)

      result = presenter.to_html

      expect(result).to eq('')
    end
  end
end
