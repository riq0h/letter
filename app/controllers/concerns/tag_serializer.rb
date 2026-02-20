# frozen_string_literal: true

module TagSerializer
  extend ActiveSupport::Concern
  include HashtagHistoryBuilder

  private

  def serialized_tag(tag, include_history: true)
    result = {
      name: tag.name,
      url: "#{Rails.application.config.activitypub.base_url}/tags/#{tag.name}"
    }

    result[:history] = include_history ? build_hashtag_history(tag) : []

    result
  end
end
