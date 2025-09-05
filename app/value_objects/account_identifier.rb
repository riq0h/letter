# frozen_string_literal: true

# アカウント識別子を表すValueObject
# username@domain形式のアカウント識別子を不変オブジェクトとして扱う
class AccountIdentifier
  attr_reader :username, :domain

  def initialize(username, domain = nil)
    @username = username&.strip
    @domain = domain&.strip&.downcase
    freeze
  end

  # 文字列からAccountIdentifierを生成
  # @username@domain、username@domain、acct:username@domain形式をサポート
  def self.new_from_string(string)
    return nil if string.blank?

    # acct:、@プレフィックスを除去
    clean_string = string.gsub(/^(acct:|@)/, '')
    parts = clean_string.split('@')

    case parts.length
    when 1
      new(parts[0]) # ローカルユーザ
    when 2
      new(parts[0], parts[1])
    end
  end

  # acct URI形式の文字列からAccountIdentifierを生成
  def self.new_from_acct_uri(acct_uri)
    return nil if acct_uri.blank?

    # acct:username@domain形式を処理
    clean_uri = acct_uri.gsub(/^(acct:|@)/, '')
    parts = clean_uri.split('@')

    return nil unless parts.length == 2

    new(parts[0], parts[1])
  end

  # メンション形式（@username）から生成
  def self.new_from_mention(mention)
    return nil if mention.blank?

    parts = mention.split('@', 2)
    return nil if parts.empty?

    new(parts[0], parts[1])
  end

  # Actorオブジェクトから生成
  def self.new_from_account(account)
    return nil unless account

    new(account.username, account.domain)
  end

  # ローカルアカウントかどうか
  def local?
    domain.nil?
  end

  # リモートアカウントかどうか
  def remote?
    domain.present?
  end

  # WebFinger URI形式に変換
  def to_webfinger_uri
    return nil if username.blank? || domain.blank?

    "acct:#{username}@#{domain}"
  end

  # 表示用の文字列に変換
  def to_s
    if local?
      username
    else
      "#{username}@#{domain}"
    end
  end

  # Mastodon互換のacct形式
  def acct
    to_s
  end

  # フルアカウント名（@付き）
  def full_acct
    "@#{self}"
  end

  # 等価性の判定
  def ==(other)
    return false unless other.is_a?(AccountIdentifier)

    username == other.username && domain == other.domain
  end

  alias eql? ==

  def hash
    [username, domain].hash
  end

  # クエリ文字列がアカウント形式かどうかを判定
  def self.account_query?(query)
    return false if query.blank?

    # URL形式のユーザプロファイルもアカウントクエリとして扱う
    return true if query.match?(/^https?:\/\/[^\/]+\/users\/[^\/]+$/)

    query.match?(/^@?[\w.-]+@[\w.-]+\.\w+$/) ||
      query.start_with?('@') ||
      domain_query?(query)
  end

  # ドメイン形式のクエリかどうかを判定
  def self.domain_query?(query)
    return false if query.blank?

    # domain.com形式（@やusernameなし）
    query.match?(/^[\w.-]+\.\w+$/) && query.exclude?('@')
  end
end
