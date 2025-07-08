# frozen_string_literal: true

module Api
  module V2
    class SearchController < Api::BaseController
      include SearchSerializationHelper

      # GET /api/v2/search
      def index
        @results = perform_search
        render_search_results
      end

      private

      def perform_search
        result = SearchInteractor.search(params, current_user)

        if result.success?
          result.results
        else
          Rails.logger.error "Search failed: #{result.error}"
          { accounts: [], statuses: [], hashtags: [] }
        end
      end

      def render_search_results
        render json: {
          accounts: @results[:accounts].map { |account| serialized_account(account) },
          statuses: @results[:statuses].map { |status| serialized_status(status) },
          hashtags: @results[:hashtags].map { |hashtag| serialized_hashtag(hashtag) }
        }
      end
    end
  end
end
