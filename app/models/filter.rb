# frozen_string_literal: true

class Filter < ApplicationRecord
  belongs_to :actor
  has_many :filter_keywords, dependent: :destroy
  has_many :filter_statuses, dependent: :destroy

  array_field :context

  validates :title, presence: true, length: { maximum: 100 }
  validates :context, presence: true
  validates :filter_action, inclusion: { in: %w[warn hide] }

  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :recent, -> { order(updated_at: :desc) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def irreversible?
    filter_action == 'hide'
  end

  def add_keyword!(keyword, whole_word: false)
    filter_keywords.find_or_create_by!(keyword: keyword, whole_word: whole_word)
  end

  def remove_keyword!(keyword)
    filter_keywords.find_by(keyword: keyword)&.destroy
  end

  def add_status!(status_id)
    filter_statuses.find_or_create_by!(status_id: status_id)
  end

  def remove_status!(status_id)
    filter_statuses.find_by(status_id: status_id)&.destroy
  end

  def matches_content?(text, content_context = 'home')
    return false unless context.include?(content_context)
    return false if expired?

    filter_keywords.any? do |filter_keyword|
      if filter_keyword.whole_word?
        text.match?(/\b#{Regexp.escape(filter_keyword.keyword)}\b/i)
      else
        text.include?(filter_keyword.keyword)
      end
    end
  end

  def matches_status?(status_id, content_context = 'home')
    return false unless context.include?(content_context)
    return false if expired?

    filter_statuses.exists?(status_id: status_id)
  end
end
