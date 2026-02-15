# frozen_string_literal: true

module Api
  module V1
    class FollowRequestsController < Api::BaseController
      include AccountSerializer
      include RelationshipSerializer

      before_action :doorkeeper_authorize!, only: %i[index authorize reject]
      before_action :require_user!, only: %i[index authorize reject]
      before_action :set_follow_request, only: %i[authorize reject]

      # GET /api/v1/follow_requests
      def index
        follow_requests = Follow.where(target_actor: current_user, accepted: false)
                                .includes(:actor)
                                .order(created_at: :desc)

        accounts = follow_requests.map { |follow| serialized_account(follow.actor) }
        render json: accounts
      end

      # POST /api/v1/follow_requests/:id/authorize
      def authorize
        if @follow_request.accepted?
          render_validation_failed('Follow request already authorized')
          return
        end

        @follow_request.update!(accepted: true, accepted_at: Time.current)
        render json: serialized_relationship(@follow_request.actor)
      end

      # POST /api/v1/follow_requests/:id/reject
      def reject
        if @follow_request.accepted?
          render_validation_failed('Follow request already authorized')
          return
        end

        @follow_request.destroy!
        render json: serialized_relationship(@follow_request.actor)
      end

      private

      def set_follow_request
        @follow_request = Follow.where(target_actor: current_user, accepted: false)
                                .find_by(id: params[:id])

        return if @follow_request

        render_not_found('Follow request')
      end
    end
  end
end
