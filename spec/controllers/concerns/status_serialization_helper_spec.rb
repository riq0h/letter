# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusSerializationHelper do
  # テスト用のダミーコントローラでconcernをinclude
  let(:test_class) do
    Class.new do
      include StatusSerializationHelper
      include TextLinkingHelper

      # parse_content_links_onlyスタブ
      def parse_content_links_only(content)
        content
      end

      # current_userスタブ
      def current_user
        nil
      end

      def params
        {}
      end
    end
  end

  let(:helper) { test_class.new }

  describe '#gsub_outside_a_tags' do
    it 'replaces text outside anchor tags' do
      content = '<p>Hello @user@example.com</p>'
      result = helper.send(:gsub_outside_a_tags, content, '@user@example.com', '[REPLACED]')

      expect(result).to include('[REPLACED]')
    end

    it 'does not replace text inside anchor tag href' do
      content = '<a href="https://example.com/@user@example.com">link</a>'
      result = helper.send(:gsub_outside_a_tags, content, '@user@example.com', '[REPLACED]')

      expect(result).to include('href="https://example.com/@user@example.com"')
      expect(result).not_to include('[REPLACED]')
    end

    it 'does not replace text inside anchor tag content' do
      content = '<a href="https://example.com">@user@example.com</a>'
      result = helper.send(:gsub_outside_a_tags, content, '@user@example.com', '[REPLACED]')

      expect(result).not_to include('[REPLACED]')
    end

    it 'replaces outside while preserving inside' do
      content = '@user@example.com wrote <a href="https://site.com/@user@example.com">a post</a>'
      result = helper.send(:gsub_outside_a_tags, content, '@user@example.com', '[REPLACED]')

      expect(result).to start_with('[REPLACED] wrote')
      expect(result).to include('href="https://site.com/@user@example.com"')
    end

    it 'handles URL with mention pattern in both href and text' do
      content = '🔗 <a href="https://qbox.example.com/u/@alice@remote.example.com">https://qbox.example.com/u/@alice@remote.example.com</a>'
      result = helper.send(:gsub_outside_a_tags, content, '@alice@remote.example.com', '[MENTION]')

      # href内もテキスト内も置換されない
      expect(result).to include('href="https://qbox.example.com/u/@alice@remote.example.com"')
      expect(result).to include('>https://qbox.example.com/u/@alice@remote.example.com</a>')
      expect(result).not_to include('[MENTION]')
    end

    it 'works with no anchor tags present' do
      content = 'Hello @user@example.com world'
      result = helper.send(:gsub_outside_a_tags, content, '@user@example.com', '[REPLACED]')

      expect(result).to eq('Hello [REPLACED] world')
    end
  end

  describe '#parse_content_for_api_with_mentions' do
    let(:remote_actor) { create(:actor, :remote) }

    it 'does not break URLs containing mention patterns' do
      # URL内にメンションパターンを含むコンテンツ（外部サービスのプロフィールURL等）
      content = '<p>🔗 <a href="https://qbox.example.com/u/@alice@remote.example.com">https://qbox.example.com/u/@alice@remote.example.com</a></p>'
      status = create(:activity_pub_object, actor: remote_actor, content: content)

      # 不正なMentionレコードが存在する場合でもHTMLが壊れないことを検証
      mentioned_actor = create(:actor, :remote, username: 'alice', domain: 'remote.example.com')
      status.mentions.create!(actor: mentioned_actor)

      result = helper.send(:parse_content_for_api_with_mentions, status)

      # hrefが維持されること
      expect(result).to include('href="https://qbox.example.com/u/@alice@remote.example.com"')
      # ">が露出しないこと
      expect(result).not_to include('@alice">')
      # ネストした<a>タグが生成されないこと
      expect(result).not_to include('<a href="https://qbox.example.com/u/<a')
    end
  end
end
