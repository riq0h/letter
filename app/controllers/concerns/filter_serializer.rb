# frozen_string_literal: true

module FilterSerializer
  extend ActiveSupport::Concern

  private

  def serialized_filter(filter)
    {
      id: filter.id.to_s,
      title: filter.title,
      context: filter.context,
      expires_at: filter.expires_at&.iso8601,
      filter_action: filter.filter_action,
      keywords: filter.filter_keywords.map { |keyword| serialized_filter_keyword(keyword) },
      statuses: filter.filter_statuses.map { |status| serialized_filter_status(status) }
    }
  end

  def serialized_filter_keyword(keyword)
    {
      id: keyword.id.to_s,
      keyword: keyword.keyword,
      whole_word: keyword.whole_word
    }
  end

  def serialized_filter_status(filter_status)
    {
      id: filter_status.id.to_s,
      status_id: filter_status.status_id
    }
  end
end
