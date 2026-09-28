# frozen_string_literal: true

require 'rails_helper'

# 同名絵文字が複数サーバ(とローカル)にある場合の選択順: 指定ドメイン → ローカル → 他ドメイン
RSpec.describe EmojiPresenter do
  # 同名の別サーバ版(選ばれてはいけない側)
  before { create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'other.example') }

  let!(:own) { create(:custom_emoji, :remote, shortcode: 'blobcat', domain: 'mattyaski.co') }

  describe '#to_html' do
    it '指定ドメインの版で描画する' do
      html = described_class.present_with_emojis(':blobcat:', domain: 'mattyaski.co')

      expect(html).to include(%(src="#{own.image_url}"))
    end

    it 'ローカルに同名があってもリモートの人には相手ドメインの版を使う' do
      local = build(:custom_emoji, :local, shortcode: 'blobcat')
      local.image.attach(io: StringIO.new('dummy'), filename: 'blobcat.png', content_type: 'image/png')
      local.save!
      html = described_class.present_with_emojis(':blobcat:', domain: 'mattyaski.co')

      expect(html).to include(%(src="#{own.image_url}"))
      expect(html).not_to include(local.url)
    end

    it '指定ドメインに無ければ他ドメインへフォールバックする' do
      html = described_class.present_with_emojis(':blobcat:', domain: 'nowhere.example')

      expect(html).to include('<img')
    end
  end

  describe '#used_emojis' do
    it '指定ドメインの版を返す' do
      expect(described_class.extract_emojis_from(':blobcat:', domain: 'mattyaski.co')).to eq([own])
    end
  end
end
