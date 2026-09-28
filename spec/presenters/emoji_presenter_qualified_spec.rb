# frozen_string_literal: true

require 'rails_helper'

# Misskey系のドメイン修飾形 :name@host: の表示(送信側がtagを付けないケース)
RSpec.describe EmojiPresenter do
  let!(:emoji) do
    create(:custom_emoji, :remote, shortcode: 'sample_emoji', domain: 'emoji.example',
                                   image_url: 'https://media.emoji.example/sample.png')
  end

  describe '#to_html' do
    it 'キャッシュ済みの(name, host)を絵文字画像に置換する' do
      html = described_class.present_with_emojis('<p>:sample_emoji@emoji.example: 本文</p>')

      expect(html).to include('<img src="https://media.emoji.example/sample.png"')
      expect(html).not_to include('@emoji.example:')
      expect(html).to include('本文')
    end

    it '別ドメインの同名絵文字にはフォールバックしない' do
      html = described_class.present_with_emojis(':sample_emoji@other.example.com:')

      expect(html).to eq(':sample_emoji@other.example.com:')
    end

    it '無効化された絵文字は置換しない' do
      emoji.update!(disabled: true)

      expect(described_class.present_with_emojis(':sample_emoji@emoji.example:'))
        .to eq(':sample_emoji@emoji.example:')
    end

    it '通常の :shortcode: と混在しても両方処理する' do
      create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'misskey.example')
      html = described_class.present_with_emojis(':blobcat: と :sample_emoji@emoji.example:')

      expect(html.scan('<img').size).to eq(2)
    end
  end

  describe '.extract_raw_shortcodes_from' do
    it '修飾形を "name@host" トークンとして抽出する' do
      expect(described_class.extract_raw_shortcodes_from(':Sample_Emoji@emoji.example: :x_y:'))
        .to contain_exactly('Sample_Emoji@emoji.example', 'x_y')
    end
  end

  describe '#used_emojis' do
    it '修飾形は送信用の絵文字一覧に含めない' do
      expect(described_class.extract_emojis_from(':sample_emoji@emoji.example:')).to eq([])
    end
  end
end
