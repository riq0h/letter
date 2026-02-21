# frozen_string_literal: true

class Tag < ApplicationRecord
  has_many :object_tags, dependent: :destroy
  has_many :objects, through: :object_tags, class_name: 'ActivityPubObject'
  has_many :usage_histories, class_name: 'TagUsageHistory', dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 100 }
  validates :name, format: { with: /\A[\w\u0080-\uFFFF]+\z/ }

  before_validation :normalize_name

  scope :trending, -> { where(trending: true) }
  scope :popular, -> { order(usage_count: :desc) }
  scope :recent, -> { order(updated_at: :desc) }

  # display_nameを保持しつつ正規化された名前でfind_or_create
  def self.find_or_create_by_display_name(original_name)
    normalized = original_name.unicode_normalize(:nfkc).strip.downcase
    tag = find_or_create_by(name: normalized)
    return tag unless tag.persisted?

    tag.update_column(:display_name, original_name) if tag.display_name.blank? && original_name != normalized
    tag
  end

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
    self.name = name.unicode_normalize(:nfkc).strip.downcase if name.present?
  end
end
