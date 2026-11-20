# frozen_string_literal: true

# 配送に失敗し続けているサーバの記録。Mastodonの配送失敗の扱い(DeliveryFailureTracker)に合わせ、
# 失敗が一定期間続いたサーバへの配送だけを止める。配送か受信に成功すれば記録を消して再開する。
# 配送を止めてもフォロー関係は消さない
class UnavailableServer < ApplicationRecord
  # 配送の失敗がこの期間続いた(その間に1度も成功していない)サーバへは配送しない。
  # Mastodonは失敗した日が7日に達したら止める。その2倍の余裕を持たせる
  FAILURE_PERIOD = 14.days

  # 4xxのうち、Mastodonが再送の対象とする(=相手側の一時的な問題とみなす)もの
  RETRYABLE_CLIENT_ERRORS = [401, 408, 429].freeze

  validates :domain, presence: true, uniqueness: true
  validates :reason, inclusion: { in: %w[gone timeout error] }
  validates :first_error_at, :last_error_at, presence: true

  before_validation :normalize_domain

  # ドメインへの配送を止めているか
  def self.unavailable?(domain)
    find_by(domain: normalize_domain_name(domain))&.unavailable? || false
  end

  def unavailable?
    last_error_at - first_error_at >= FAILURE_PERIOD
  end

  # 配送失敗として数える結果か。応答が無い(タイムアウト・接続できない・名前解決できない)か、5xxなど。
  # 410などそれ以外の4xxは、相手サーバは動いていて「その宛先は無い」と答えているだけなので数えない
  def self.delivery_failure?(result)
    code = result[:code]
    return true if code.nil?

    code >= 500 || RETRYABLE_CLIENT_ERRORS.include?(code)
  end

  # 配送の失敗を記録する
  # 同じサーバ宛ての配送は並行して走るため、同時に初回の記録を作ろうとしたら作り直す
  def self.record_failure(domain, error_message = nil)
    attempts ||= 0
    reason = error_message.to_s.start_with?('Timeout') ? 'timeout' : 'error'
    server = find_or_initialize_by(domain: normalize_domain_name(domain))
    now = Time.current

    if server.new_record?
      server.assign_attributes(reason: reason, first_error_at: now, last_error_at: now, error_count: 1,
                               last_error_message: error_message, auto_detected: true)
    else
      server.assign_attributes(reason: reason, last_error_at: now, error_count: server.error_count + 1,
                               last_error_message: error_message)
    end

    server.save!
    server
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    attempts += 1
    retry if attempts < 2
    raise
  end

  # 配送か受信に成功したサーバの失敗記録を消し、配送を再開する
  def self.record_success(domain)
    normalized_domain = normalize_domain_name(domain)
    where(domain: normalized_domain).delete_all if exists?(domain: normalized_domain)
  end

  # ドメインの正規化
  def self.normalize_domain_name(domain)
    return nil if domain.blank?

    domain.to_s.strip.downcase.chomp('.')
  end

  private

  def normalize_domain
    self.domain = self.class.normalize_domain_name(domain)
  end
end
