# frozen_string_literal: true

module Api
  module V1
    class FavouritesController < Api::BaseController
      include StatusSerializationHelper
      include ApiPagination

      before_action :doorkeeper_authorize!
      before_action :require_user!
      after_action :insert_pagination_headers

      # GET /api/v1/favourites
      def index
        favourites = current_user.favourites
                                 .joins(:object)
                                 .includes(object: %i[actor media_attachments mentions tags poll])
                                 .order(id: :desc)

        favourites = apply_collection_pagination(favourites, 'favourites')

        favourites = favourites.limit(limit_param)

        @paginated_items = favourites
        statuses = favourites.map(&:object)
        render json: statuses.map { |status| serialized_status(status) }
      end
    end
  end
end
