# frozen_string_literal: true

module ActivityPub
  class HtmlStripper
    # HTMLタグを除去してプレーンテキストに変換
    def self.strip(html_content)
      return '' if html_content.blank?

      # HTMLエンティティデコード
      decoded = CGI.unescapeHTML(html_content)

      # HTMLタグ除去
      plain_text = decoded.gsub(/<br\s*\/?>/i, "\n")
                          .gsub(/<\/p>/i, "\n\n")
                          .gsub(/<[^>]+>/, '')

      # 余分な空白・改行整理
      plain_text.gsub(/\n{3,}/, "\n\n")
                .gsub(/[ \t]+/, ' ')
                .strip
    end

    # HTMLの安全性チェック（Loofahベースのサニタイズ）
    def self.sanitize(html_content)
      return '' if html_content.blank?

      sanitizer = Rails::HTML5::SafeListSanitizer.new
      sanitizer.sanitize(
        html_content,
        tags: %w[p br a span em strong b i u del blockquote pre code ul ol li h1 h2 h3 h4 h5 h6 div],
        attributes: %w[href class rel target translate]
      )
    end

    # メンション抽出
    def self.extract_mentions(html_content)
      return [] if html_content.blank?

      mentions = []

      # @username@domain パターン
      html_content.scan(/@(\w+)@([\w\.-]+)/) do |username, domain|
        mentions << "#{username}@#{domain}"
      end

      # <a href="..." class="mention">@username</a> パターン
      mention_pattern = /<a[^>]+href=["']([^"']+)["'][^>]*class=["'][^"']*mention[^"']*["'][^>]*>@(\w+)<\/a>/i
      html_content.scan(mention_pattern) do |href, username|
        mentions << { href: href, username: username }
      end

      mentions.uniq
    end

    # ハッシュタグ抽出
    def self.extract_hashtags(html_content)
      return [] if html_content.blank?

      hashtags = []

      # #hashtag パターン（日本語ハッシュタグにも対応）
      html_content.scan(/#([a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]+)/) do |tag|
        hashtags << tag[0]
      end

      # <a href="..." class="hashtag">#tag</a> パターン
      hashtag_pattern =
        /<a[^>]+href=["']([^"']+)["'][^>]*class=["'][^"']*hashtag[^"']*["'][^>]*>
        \#([a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]+)<\/a>/ix
      html_content.scan(hashtag_pattern) do |href, tag|
        hashtags << { href: href, tag: tag }
      end

      hashtags.uniq
    end
  end
end
