# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TextLinkingHelper, type: :helper do
  describe '#auto_link_urls' do
    context 'with plain text' do
      it 'returns empty string for blank text' do
        expect(helper.auto_link_urls('')).to eq('')
        expect(helper.auto_link_urls(nil)).to eq('')
      end

      it 'links URLs in plain text' do
        text = 'Check out https://example.com for more info'
        result = helper.auto_link_urls(text)

        expect(result).to include('<a href="https://example.com"')
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener noreferrer"')
        expect(result).to include('example.com</a>')
      end

      it 'links multiple URLs' do
        text = 'Visit https://example.com and https://test.org'
        result = helper.auto_link_urls(text)

        expect(result).to include('href="https://example.com"')
        expect(result).to include('href="https://test.org"')
      end

      it 'processes text with angle brackets as HTML' do
        text = 'Text with <script>alert("xss")</script> and https://example.com'
        result = helper.auto_link_urls(text)

        # <と>が含まれているためHTMLとして処理される
        expect(result).to include('href="https://example.com"')
      end

      it 'converts newlines to br tags' do
        text = "Line 1\nLine 2\nhttps://example.com"
        result = helper.auto_link_urls(text)

        expect(result).to include('<br>')
        expect(result).to include('href="https://example.com"')
      end
    end

    context 'with mentions' do
      it 'links mentions in plain text' do
        text = 'Hello @user@example.com how are you?'
        result = helper.auto_link_urls(text)

        expect(result).to include('<a href="https://example.com/users/user"')
        expect(result).to include('@user</span></a>')
      end

      it 'links both URLs and mentions' do
        text = 'Check @user@example.com and visit https://test.org'
        result = helper.auto_link_urls(text)

        expect(result).to include('href="https://example.com/users/user"')
        expect(result).to include('href="https://test.org"')
      end
    end

    context 'with HTML content' do
      it 'preserves existing HTML tags' do
        html = 'Check <strong>this</strong> and https://example.com'
        result = helper.auto_link_urls(html)

        expect(result).to include('<strong>this</strong>')
        expect(result).to include('href="https://example.com"')
      end

      it 'processes URLs and HTML content' do
        html = '<p>Check this and https://new.com</p>'
        result = helper.auto_link_urls(html)

        # HTML構造が保持される
        expect(result).to include('<p>')
        # URLがリンク化される
        expect(result).to include('href="https://new.com"')
      end

      it 'preserves complex HTML structure' do
        html = '<p>Text with <em>emphasis</em> and https://example.com</p>'
        result = helper.auto_link_urls(html)

        expect(result).to include('<p>')
        expect(result).to include('<em>emphasis</em>')
        expect(result).to include('href="https://example.com"')
      end
    end
  end

  describe '#mask_protocol' do
    it 'removes https:// from URLs' do
      expect(helper.send(:mask_protocol, 'https://example.com')).to eq('example.com')
      expect(helper.send(:mask_protocol, 'https://subdomain.example.com/path')).to eq('subdomain.example.com/path')
    end

    it 'preserves URLs without https://' do
      expect(helper.send(:mask_protocol, 'http://example.com')).to eq('http://example.com')
      expect(helper.send(:mask_protocol, 'ftp://example.com')).to eq('ftp://example.com')
      expect(helper.send(:mask_protocol, 'example.com')).to eq('example.com')
    end
  end

  describe '#build_mention_url' do
    it 'builds correct mention URLs' do
      result = helper.send(:build_mention_url, 'username', 'example.com')
      expect(result).to eq('https://example.com/users/username')
    end

    it 'sanitizes username and domain' do
      result = helper.send(:build_mention_url, 'user<script>', 'evil.com')
      expect(result).to eq('https://evil.com/users/userscript')
    end

    it 'returns # for empty username or domain' do
      expect(helper.send(:build_mention_url, '', 'example.com')).to eq('#')
      expect(helper.send(:build_mention_url, 'user', '')).to eq('#')
      expect(helper.send(:build_mention_url, '<script>', '>')).to eq('#')
    end

    it 'URL encodes special characters' do
      result = helper.send(:build_mention_url, 'user name', 'ex ample.com')
      expect(result).to eq('https://example.com/users/username')
    end
  end

  describe '#extract_urls_from_content' do
    it 'returns empty array for blank content' do
      expect(helper.send(:extract_urls_from_content, '')).to eq([])
      expect(helper.send(:extract_urls_from_content, nil)).to eq([])
    end

    it 'extracts URLs from href attributes' do
      html = '<p>Check <a href="https://example.com">this link</a></p>'
      result = helper.send(:extract_urls_from_content, html)

      expect(result).to include('https://example.com')
    end

    it 'extracts plain text URLs' do
      text = 'Visit https://example.com and https://test.org for more info'
      result = helper.send(:extract_urls_from_content, text)

      expect(result).to include('https://example.com')
      expect(result).to include('https://test.org')
    end

    it 'removes duplicates' do
      content = '<a href="https://example.com">Link</a> and https://example.com again'
      result = helper.send(:extract_urls_from_content, content)

      expect(result.count('https://example.com')).to eq(1)
    end

    it 'filters out invalid URLs' do
      content = 'Visit https://example.com/users/test and https://example.com/image.jpg'
      result = helper.send(:extract_urls_from_content, content)

      expect(result).not_to include('https://example.com/users/test')
      expect(result).not_to include('https://example.com/image.jpg')
    end

    it 'filters out hashtag links' do
      content = '<p>Check this <a href="/tags/ruby" class="hashtag">#ruby</a> and <a href="https://example.com">normal link</a></p>'
      result = helper.send(:extract_urls_from_content, content)

      expect(result).not_to include('/tags/ruby')
      expect(result).to include('https://example.com')
    end
  end

  describe '#valid_preview_url?' do
    it 'accepts valid HTTP/HTTPS URLs' do
      expect(helper.send(:valid_preview_url?, 'https://example.com')).to be true
      expect(helper.send(:valid_preview_url?, 'http://example.com')).to be true
    end

    it 'rejects invalid schemes' do
      expect(helper.send(:valid_preview_url?, 'ftp://example.com')).to be false
      expect(helper.send(:valid_preview_url?, 'javascript:alert(1)')).to be false
    end

    it 'rejects URLs without host' do
      expect(helper.send(:valid_preview_url?, 'https://')).to be false
      expect(helper.send(:valid_preview_url?, 'https:///path')).to be false
    end

    it 'rejects user/mention URLs' do
      expect(helper.send(:valid_preview_url?, 'https://example.com/users/username')).to be false
      expect(helper.send(:valid_preview_url?, 'https://example.com/@username')).to be false
    end

    it 'rejects media file URLs' do
      %w[.jpg .jpeg .png .gif .webp .mp4 .mp3 .wav .avi .mov .pdf].each do |ext|
        url = "https://example.com/file#{ext}"
        expect(helper.send(:valid_preview_url?, url)).to be false
      end
    end

    it 'accepts valid content URLs' do
      expect(helper.send(:valid_preview_url?, 'https://example.com/article')).to be true
      expect(helper.send(:valid_preview_url?, 'https://example.com/blog/post-title')).to be true
      expect(helper.send(:valid_preview_url?, 'https://news.example.com/2023/story')).to be true
    end

    it 'handles malformed URLs gracefully' do
      expect(helper.send(:valid_preview_url?, 'not-a-url')).to be false
      expect(helper.send(:valid_preview_url?, 'https://[invalid')).to be false
    end

    it 'rejects blank URLs' do
      expect(helper.send(:valid_preview_url?, nil)).to be false
      expect(helper.send(:valid_preview_url?, '')).to be false
    end
  end

  describe 'private methods' do
    describe '#escape_and_format_text' do
      it 'sanitizes and escapes HTML' do
        text = '<script>alert("xss")</script>Hello\nWorld'
        result = helper.send(:escape_and_format_text, text)

        expect(result).to eq('alert(&quot;xss&quot;)Hello\\nWorld')
      end

      it 'converts newlines to br tags' do
        text = "Line 1\nLine 2\nLine 3"
        result = helper.send(:escape_and_format_text, text)

        expect(result).to eq('Line 1<br>Line 2<br>Line 3')
      end
    end

    describe '#apply_url_links' do
      it 'converts URLs to anchor tags' do
        text = 'Visit https://example.com for info'
        result = helper.send(:apply_url_links, text)

        expect(result).to include('<a href="https://example.com"')
        expect(result).to include('target="_blank"')
        expect(result).to include('example.com</a>')
      end

      it 'handles multiple URLs' do
        text = 'https://first.com and https://second.com'
        result = helper.send(:apply_url_links, text)

        expect(result).to include('href="https://first.com"')
        expect(result).to include('href="https://second.com"')
      end
    end

    describe '#apply_mention_links' do
      it 'converts mentions to anchor tags' do
        text = 'Hello @user@example.com!'
        result = helper.send(:apply_mention_links, text)

        expect(result).to include('<a href="https://example.com/users/user"')
        expect(result).to include('@user</span></a>')
      end

      it 'handles multiple mentions' do
        text = '@alice@first.com and @bob@second.com'
        result = helper.send(:apply_mention_links, text)

        expect(result).to include('https://first.com/users/alice')
        expect(result).to include('https://second.com/users/bob')
      end
    end
  end
end
