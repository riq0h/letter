# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusSerializer do
  # StatusSerializer を include しただけの軽量ハーネス
  let(:test_class) { Class.new { include StatusSerializer } }
  let(:helper) { test_class.new }
  let(:domain) { 'azkey.azuki.blue' }
  let(:actor_stub) { Struct.new(:domain) }
  let(:status_stub) { Struct.new(:content, :actor, :id) }
  # DB保存値はdowncaseで統一されている
  let!(:emoji) { create(:custom_emoji, :remote, shortcode: 'a_blobcat_attention', domain: domain) }

  def status_with(content)
    status_stub.new(content, actor_stub.new(domain), '1')
  end

  describe '#serialized_emojis' do
    context 'when resolving directly from the DB (no preloaded cache)' do
      it '本文に現れた大文字小文字のままショートコードを出力する' do
        result = helper.send(:serialized_emojis, status_with('豚汁まで用意:A_BlobCat_Attention:'))
        expect(result.pluck(:shortcode)).to eq(['A_BlobCat_Attention'])
        expect(result.first[:url]).to eq(emoji.url)
      end

      it '小文字表記の本文も解決できる' do
        result = helper.send(:serialized_emojis, status_with('x :a_blobcat_attention: y'))
        expect(result.pluck(:shortcode)).to eq(['a_blobcat_attention'])
      end

      it '対応する絵文字が無いショートコードは無視する' do
        result = helper.send(:serialized_emojis, status_with(':no_such_emoji:'))
        expect(result).to eq([])
      end
    end

    context 'when using a preloaded emoji cache' do
      before do
        helper.instance_variable_set(:@emoji_cache,
                                     { local: {}, remote: { "a_blobcat_attention:#{domain}" => emoji } })
      end

      it '本文の大文字小文字を保持しつつキャッシュのURLを解決する' do
        result = helper.send(:serialized_emojis, status_with(':A_BlobCat_Attention:'))
        expect(result.pluck(:shortcode)).to eq(['A_BlobCat_Attention'])
        expect(result.first[:url]).to eq(emoji.url)
      end

      it 'ドメイン無指定フォールバックkeyでも解決できる' do
        helper.instance_variable_set(:@emoji_cache, { local: {}, remote: { 'a_blobcat_attention:' => emoji } })
        result = helper.send(:serialized_emojis, status_with(':A_BlobCat_Attention:'))
        expect(result.pluck(:shortcode)).to eq(['A_BlobCat_Attention'])
      end
    end

    it 'content が空なら空配列を返す' do
      expect(helper.send(:serialized_emojis, status_with(''))).to eq([])
    end
  end
end
