# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSerializer do
  let(:test_class) do
    Class.new do
      include AccountSerializer
      include TextLinkingHelper

      def current_user
        nil
      end

      def params
        {}
      end

      # sanitize_html_for_displayスタブ
      def sanitize_html_for_display(content)
        content
      end
    end
  end

  let(:helper) { test_class.new }

  describe '#sanitize_plain_text' do
    it 'returns plain text unchanged' do
      expect(helper.send(:sanitize_plain_text, 'Hello World')).to eq('Hello World')
    end

    it 'strips <p> tags' do
      expect(helper.send(:sanitize_plain_text, '<p>Hello</p>')).to eq('Hello')
    end

    it 'strips nested block tags' do
      expect(helper.send(:sanitize_plain_text, '<div><p>Hello</p></div>')).to eq('Hello')
    end

    it 'preserves custom emoji shortcodes from img tags' do
      html = 'Cat lover <img src="https://example.com/blobcat.png" alt=":blobcat:" class="custom-emoji" />'
      result = helper.send(:sanitize_plain_text, html)

      expect(result).to eq('Cat lover :blobcat:')
    end

    it 'preserves emoji shortcodes in plain text' do
      expect(helper.send(:sanitize_plain_text, ':blobcat: fan')).to eq(':blobcat: fan')
    end

    it 'handles mixed HTML and emoji img tags' do
      html = '<p>Hello <img src="https://example.com/smile.png" alt=":smile:" class="custom-emoji" /> World</p>'
      result = helper.send(:sanitize_plain_text, html)

      expect(result).to eq('Hello :smile: World')
    end
  end

  describe '#sanitize_field_html' do
    it 'returns value without HTML unchanged' do
      expect(helper.send(:sanitize_field_html, 'plain text')).to eq('plain text')
    end

    it 'strips <p> tags keeping content' do
      expect(helper.send(:sanitize_field_html, '<p>Hello World</p>')).to eq('Hello World')
    end

    it 'strips invisible spans' do
      html = '<a href="https://example.com"><span class="invisible">https://</span>example.com</a>'
      result = helper.send(:sanitize_field_html, html)

      expect(result).to include('example.com')
      expect(result).not_to include('invisible')
    end

    it 'unwraps ellipsis spans' do
      html = '<span class="ellipsis">example.c</span>'
      result = helper.send(:sanitize_field_html, html)

      expect(result).to eq('example.c')
    end

    it 'preserves <a> tags' do
      html = '<p><a href="https://example.com">example.com</a></p>'
      result = helper.send(:sanitize_field_html, html)

      expect(result).to include('<a href="https://example.com">')
      expect(result).not_to include('<p>')
    end

    it 'preserves emoji <img> tags' do
      html = '<p>Hello <img src="https://example.com/emoji.png" alt=":smile:" class="custom-emoji" /></p>'
      result = helper.send(:sanitize_field_html, html)

      expect(result).to include('<img')
      expect(result).to include(':smile:')
      expect(result).not_to include('<p>')
    end

    it 'strips heading tags' do
      expect(helper.send(:sanitize_field_html, '<h1>Title</h1>')).to eq('Title')
    end

    it 'strips list tags' do
      expect(helper.send(:sanitize_field_html, '<ul><li>Item</li></ul>')).to eq('Item')
    end

    it 'collapses whitespace' do
      html = "<p>Hello</p>\n\n<p>World</p>"
      result = helper.send(:sanitize_field_html, html)

      expect(result).to eq('Hello World')
    end
  end

  describe '#format_field_value_for_api' do
    it 'returns empty string for blank value' do
      expect(helper.send(:format_field_value_for_api, '')).to eq('')
    end

    it 'strips <p> tags and preserves link' do
      html = '<p><a href="https://example.com" rel="me">example.com</a></p>'
      result = helper.send(:format_field_value_for_api, html)

      expect(result).to include('<a href="https://example.com"')
      expect(result).not_to include('<p>')
    end

    it 'converts plain URL to link' do
      result = helper.send(:format_field_value_for_api, 'https://example.com')

      expect(result).to include('<a href="https://example.com"')
      expect(result).to include('example.com</a>')
    end

    it 'escapes plain text without HTML or URL' do
      result = helper.send(:format_field_value_for_api, 'Just text & stuff')

      expect(result).to eq('Just text &amp; stuff')
    end

    it 'does not expose <p> tags as escaped text' do
      result = helper.send(:format_field_value_for_api, '<p>Some text</p>')

      expect(result).not_to include('&lt;p&gt;')
      expect(result).not_to include('<p>')
      expect(result).to include('Some text')
    end
  end
end
