# frozen_string_literal: true

class Relay < ApplicationRecord
  validates :inbox_url, presence: true, uniqueness: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :state, inclusion: { in: %w[idle pending accepted rejected] }

  has_many :activity_pub_objects, dependent: :nullify

  scope :enabled, -> { where(state: 'accepted') }
  scope :pending, -> { where(state: 'pending') }
  scope :accepted, -> { enabled }

  before_validation :normalize_inbox_url
  before_destroy :ensure_disabled

  def pending?
    state == 'pending'
  end

  def accepted?
    state == 'accepted'
  end

  def rejected?
    state == 'rejected'
  end

  def idle?
    state == 'idle'
  end

  def enable!
    update!(state: 'accepted')
  end

  def disable!
    update!(state: 'idle')
  end

  def reject!
    update!(state: 'rejected')
  end

  # リレーのアクターURIを取得（DB保存値優先、未設定時はinbox_urlから導出）
  def actor_uri
    self[:actor_uri].presence || derive_actor_uri
  end

  # リレーのドメインを取得
  def domain
    return if inbox_url.blank?

    begin
      URI.parse(inbox_url).host
    rescue URI::InvalidURIError
      nil
    end
  end

  private

  def derive_actor_uri
    return if inbox_url.blank?

    uri = URI.parse(inbox_url)
    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port != uri.default_port}/actor"
  rescue URI::InvalidURIError
    nil
  end

  def ensure_disabled
    return unless accepted?

    RelayUnfollowService.new.call(self)
  rescue StandardError => e
    Rails.logger.error "Failed to unfollow relay on destroy: #{e.message}"
  end

  def normalize_inbox_url
    return if inbox_url.blank?

    self.inbox_url = inbox_url.strip
    # /inbox で終わっていない場合は追加
    return if inbox_url.end_with?('/inbox')

    self.inbox_url = "#{inbox_url}/inbox"
  end
end
