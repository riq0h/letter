# frozen_string_literal: true

class Tag < ApplicationRecord
  has_many :object_tags, dependent: :destroy
  has_many :objects, through: :object_tags, class_name: 'ActivityPubObject'

  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 100 }
  validates :name, format: { with: /\A[a-zA-Z0-9_\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]+\z/ }

  before_validation :normalize_name

  scope :trending, -> { where(trending: true) }
  scope :popular, -> { order(usage_count: :desc) }
  scope :recent, -> { order(updated_at: :desc) }

  def to_param
    name
  end

  def increment_usage!
    self.class.update_counters(id, usage_count: 1)
    touch
  end

  def decrement_usage!
    self.class.where(id: id).where('usage_count > 0').update_all('usage_count = usage_count - 1')
  end

  private

  def normalize_name
    self.name = name.strip.downcase if name.present?
  end
end
