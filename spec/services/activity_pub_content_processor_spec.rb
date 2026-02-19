# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubContentProcessor do
  let(:actor) { create(:actor, :remote) }

  describe '#extract_mentions' do
    it 'does not extract mentions from URLs inside anchor tags' do
      # URL内にメンションパターンを含むHTML（外部サービスのプロフィールURL等）
      content = '🔗 <a href="https://qbox.example.com/u/@alice@remote.example.com">https://qbox.example.com/u/@alice@remote.example.com</a>'
      object = create(:activity_pub_object, actor: actor, content: content)

      # URL内のメンションパターンがMention対象にならないことを検証
      processor = described_class.new(object)
      processor.send(:extract_mentions)

      expect(object.mentions.where(actor: actor)).to be_empty
    end

    it 'extracts mentions from plain text outside anchor tags' do
      local_actor = create(:actor, local: true, username: 'testuser')
      content = '<p>Hello @testuser this is a mention</p>'
      object = create(:activity_pub_object, actor: actor, content: content)

      processor = described_class.new(object)
      processor.send(:extract_mentions)

      expect(object.mentions.find_by(actor: local_actor)).to be_present
    end

    it 'extracts mentions outside links while ignoring those inside links' do
      mentioned_actor = create(:actor, :remote, username: 'someone', domain: 'example.com')
      content = '<p>@someone@example.com wrote <a href="https://example.com/@someone@example.com/posts/1">a post</a></p>'
      object = create(:activity_pub_object, actor: actor, content: content)

      processor = described_class.new(object)
      processor.send(:extract_mentions)

      # テキスト部分の@someone@example.comはメンションとして抽出される
      expect(object.mentions.find_by(actor: mentioned_actor)).to be_present
      # 重複が作られないこと
      expect(object.mentions.where(actor: mentioned_actor).count).to eq(1)
    end
  end
end
