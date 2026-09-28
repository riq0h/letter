# frozen_string_literal: true

require 'rails_helper'

# Misskey系のドメイン修飾形 :name@host: の表示(送信側がtagを付けないケース)
RSpec.describe EmojiPresenter do
  let!(:emoji) do
    create(:custom_emoji, :remote, shortcode: 'yojo_art_online', domain: 'alone.aokaga.work',
                                   image_url: 'https://media.aokaga.work/yojo.png')
  end

  describe '#to_html' do
    it 'キャッシュ済みの(name, host)を絵文字画像に置換する' do
      html = described_class.present_with_emojis('<p>:yojo_art_online@alone.aokaga.work: 謎絵文字すぎ</p>')

      expect(html).to include('<img src="https://media.aokaga.work/yojo.png"')
      expect(html).not_to include('@alone.aokaga.work:')
      expect(html).to include('謎絵文字すぎ')
    end

    it '別ドメインの同名絵文字にはフォールバックしない' do
      html = described_class.present_with_emojis(':yojo_art_online@other.example.com:')

      expect(html).to eq(':yojo_art_online@other.example.com:')
    end

    it '無効化された絵文字は置換しない' do
      emoji.update!(disabled: true)

      expect(described_class.present_with_emojis(':yojo_art_online@alone.aokaga.work:'))
        .to eq(':yojo_art_online@alone.aokaga.work:')
    end

    it '通常の :shortcode: と混在しても両方処理する' do
      create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'misskey.example')
      html = described_class.present_with_emojis(':blobcat: と :yojo_art_online@alone.aokaga.work:')

      expect(html.scan('<img').size).to eq(2)
    end
  end

  describe '.extract_raw_shortcodes_from' do
    it '修飾形を "name@host" トークンとして抽出する' do
      expect(described_class.extract_raw_shortcodes_from(':Yojo_Art_Online@alone.aokaga.work: :x_y:'))
        .to contain_exactly('Yojo_Art_Online@alone.aokaga.work', 'x_y')
    end
  end

  describe '#used_emojis' do
    it '修飾形は送信用の絵文字一覧に含めない' do
      expect(described_class.extract_emojis_from(':yojo_art_online@alone.aokaga.work:')).to eq([])
    end
  end
end
