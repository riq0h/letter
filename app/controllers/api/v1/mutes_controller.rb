# frozen_string_literal: true

module Api
  module V1
    class MutesController < Api::BaseController
      include AccountSerializer
      include ApiPagination

      before_action :doorkeeper_authorize!
      before_action :require_user!
      after_action :insert_pagination_headers

      # GET /api/v1/mutes
      def index
        mutes = current_user.mutes
                            .includes(:target_actor)
                            .order(id: :desc)

        mutes = apply_collection_pagination(mutes, 'mutes')

        mutes = mutes.limit(limit_param)

        @paginated_items = mutes
        render json: mutes.map { |mute| serialized_account(mute.target_actor) }
      end
    end
  end
end
