# frozen_string_literal: true

class UnavailableServer < ApplicationRecord
  validates :domain, presence: true, uniqueness: true
  validates :reason, inclusion: { in: %w[gone timeout error] }
  validates :first_error_at, :last_error_at, presence: true

  scope :gone_servers, -> { where(reason: 'gone') }
  scope :recent_errors, -> { where('last_error_at > ?', 24.hours.ago) }
  scope :persistent_errors, -> { where(error_count: 3..) }

  before_validation :normalize_domain

  # ドメインが配信不可能かチェック
  def self.unavailable?(domain)
    exists?(domain: normalize_domain_name(domain))
  end

  # 410 Gone応答を記録
  def self.record_gone_response(domain, error_message = nil)
    record_error(domain, 'gone', error_message)
  end

  # エラーを記録（410以外）
  def self.record_error(domain, reason = 'error', error_message = nil)
    normalized_domain = normalize_domain_name(domain)

    server = find_or_initialize_by(domain: normalized_domain)

    if server.new_record?
      server.assign_attributes(
        reason: reason,
        first_error_at: Time.current,
        last_error_at: Time.current,
        error_count: 1,
        last_error_message: error_message,
        auto_detected: true
      )
    else
      server.assign_attributes(
        reason: reason,
        last_error_at: Time.current,
        error_count: server.error_count + 1,
        last_error_message: error_message
      )
    end

    server.save!
    server
  end

  # ドメインの配信停止を解除
  def self.mark_available(domain)
    normalized_domain = normalize_domain_name(domain)
    where(domain: normalized_domain).delete_all
  end

  # ドメインの正規化
  def self.normalize_domain_name(domain)
    return nil if domain.blank?

    domain.to_s.strip.downcase.chomp('.')
  end

  # 関連するフォロー関係を削除
  def cleanup_relationships!
    # このドメインのアクターをすべて取得
    Actor.where(domain: domain)

    # フォロー関係を削除
    Follow.joins(:actor).where(actors: { domain: domain }).delete_all
    Follow.joins(:target_actor).where(actors: { domain: domain }).delete_all

    Rails.logger.info "🧹 Cleaned up relationships for unavailable domain: #{domain}"
  end

  private

  def normalize_domain
    self.domain = self.class.normalize_domain_name(domain)
  end
end
