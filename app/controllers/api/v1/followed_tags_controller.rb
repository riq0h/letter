# frozen_string_literal: true

module Api
  module V1
    class FollowedTagsController < Api::BaseController
      include TagSerializer

      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v1/followed_tags
      def index
        limit = [params.fetch(:limit, 100).to_i, 200].min
        followed_tags = current_user.followed_tags.includes(:tag).recent.limit(limit)

        tags = followed_tags.map do |followed_tag|
          serialized_tag(followed_tag.tag, include_history: true).merge(following: true)
        end

        render json: tags
      end
    end
  end
end
