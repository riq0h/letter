# frozen_string_literal: true

require 'ipaddr'
require 'resolv'

# SSRF（Server-Side Request Forgery）防止モジュール
# 全てのアウトバウンドHTTPクライアントでincludeして使用する
module SsrfProtection
  extend ActiveSupport::Concern

  PRIVATE_RANGES = [
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('169.254.0.0/16'), # link-local
    IPAddr.new('0.0.0.0/8'),
    IPAddr.new('::1/128'), # IPv6 loopback
    IPAddr.new('::ffff:0:0/96'), # IPv4-mapped IPv6
    IPAddr.new('fc00::/7'),         # IPv6 unique local
    IPAddr.new('fe80::/10')         # IPv6 link-local
  ].freeze

  MAX_REDIRECT_DEPTH = 5

  private

  # URLがSSRF攻撃に利用される可能性があるかチェック
  def ssrf_safe_url?(url)
    uri = URI.parse(url.to_s)
    return false unless %w[http https].include?(uri.scheme)
    return false if uri.host.blank?

    !dangerous_host?(uri.host)
  rescue URI::InvalidURIError
    false
  end

  # ホスト名が危険（プライベートIP、localhost等）かチェック
  def dangerous_host?(host)
    return true if host.blank?

    # DNS解決してIPアドレスを取得（DNS rebinding対策）
    resolved_ips = resolve_host(host)
    return true if resolved_ips.empty?

    resolved_ips.any? { |ip| private_ip?(ip) }
  rescue StandardError
    true # エラーが発生した場合は安全側に倒す
  end

  def resolve_host(host)
    # 直接IPアドレスの場合はそのまま返す
    begin
      return [IPAddr.new(host)]
    rescue IPAddr::InvalidAddressError
      # ドメイン名の場合はDNS解決
    end

    Resolv.getaddresses(host).map { |addr| IPAddr.new(addr) }
  rescue Resolv::ResolvError
    []
  end

  def private_ip?(ip)
    ip = IPAddr.new(ip.to_s) unless ip.is_a?(IPAddr)
    PRIVATE_RANGES.any? { |range| range.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  # URLのSSRF安全性を検証し、危険な場合はログ出力して false を返す
  def validate_url_for_ssrf!(url)
    unless ssrf_safe_url?(url)
      Rails.logger.warn "🛡️ SSRF protection: blocked request to #{url}"
      return false
    end
    true
  end

  module ClassMethods
    def ssrf_safe_url?(url)
      new_instance = allocate
      new_instance.send(:ssrf_safe_url?, url)
    end
  end
end
