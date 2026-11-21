# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmojiFormatter do
  # Misskeyは1文字の絵文字名(:a: など)を使う
  describe 'one-character shortcodes' do
    let(:emoji) { create(:custom_emoji, :remote, shortcode: 'a', domain: 'misskey.example') }

    it 'renders a one-character emoji that the post carries' do
      html = described_class.emojify('Misskey :a: emoji', custom_emojis: { 'a' => emoji })

      expect(html).to include('emoji/a.png')
      expect(html).not_to include('Misskey :a: emoji')
    end

    it 'leaves colon-separated text alone when no such emoji exists' do
      expect(described_class.emojify('ratio a:b:c', custom_emojis: { 'a' => emoji })).to eq('ratio a:b:c')
    end
  end
end
