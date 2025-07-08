# frozen_string_literal: true

class OptimizedSearchService
  include ActiveModel::Model

  attr_accessor :query, :since_time, :until_time, :limit, :offset

  def initialize(attributes = {})
    super
    @limit ||= 30
    @offset ||= 0
  end

  delegate :search, :posts_in_time_range, :user_posts_search, to: :search_query

  def timeline(max_id: nil, min_id: nil)
    search_query.timeline(max_id: max_id, min_id: min_id)
  end

  def user_posts(actor_id, max_id: nil)
    search_query.user_posts(actor_id, max_id: max_id)
  end

  private

  def search_query
    @search_query ||= SearchQuery.new(
      query: query,
      since_time: since_time,
      until_time: until_time,
      limit: limit,
      offset: offset
    )
  end
end
