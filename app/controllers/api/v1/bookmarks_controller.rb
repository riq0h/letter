# frozen_string_literal: true

module Api
  module V1
    class BookmarksController < Api::BaseController
      include StatusSerializationHelper
      include ApiPagination

      before_action :doorkeeper_authorize!
      before_action :require_user!
      after_action :insert_pagination_headers

      # GET /api/v1/bookmarks
      def index
        bookmarks = current_user.bookmarks
                                .joins(:object)
                                .includes(object: [:actor, :media_attachments, :tags, :poll, { mentions: :actor }])
                                .order(id: :desc)

        bookmarks = apply_collection_pagination(bookmarks, 'bookmarks')

        bookmarks = bookmarks.limit(limit_param)

        @paginated_items = bookmarks
        statuses = bookmarks.map(&:object)
        preload_all_status_data(statuses)
        render json: statuses.map { |status| serialized_status(status) }
      end
    end
  end
end
