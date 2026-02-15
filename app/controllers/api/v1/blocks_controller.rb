# frozen_string_literal: true

module Api
  module V1
    class BlocksController < Api::BaseController
      include AccountSerializer
      include ApiPagination

      before_action :doorkeeper_authorize!
      before_action :require_user!
      after_action :insert_pagination_headers

      # GET /api/v1/blocks
      def index
        blocks = current_user.blocks
                             .includes(:target_actor)
                             .order(id: :desc)

        blocks = apply_collection_pagination(blocks, 'blocks')

        blocks = blocks.limit(limit_param)

        @paginated_items = blocks
        render json: blocks.map { |block| serialized_account(block.target_actor) }
      end
    end
  end
end
