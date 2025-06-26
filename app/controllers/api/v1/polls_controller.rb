# frozen_string_literal: true

module Api
  module V1
    class PollsController < Api::BaseController
      before_action :doorkeeper_authorize!
      before_action :require_user!
      before_action :set_poll, only: %i[show vote]

      # GET /api/v1/polls/:id
      def show
        render json: serialize_poll(@poll, current_user)
      end

      # POST /api/v1/polls/:id/votes
      def vote
        choices = parse_vote_choices

        if @poll.vote_for!(current_user, choices)
          render json: serialize_poll(@poll, current_user)
        else
          render_invalid_action('Invalid vote or poll expired')
        end
      end

      private

      def set_poll
        @poll = Poll.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Poll')
      end

      def parse_vote_choices
        choices = params[:choices]
        return [] unless choices.is_a?(Array)

        choices.map(&:to_i).select { |choice| choice >= 0 }
      end

      def serialize_poll(poll, current_actor = nil)
        result = poll.to_mastodon_api

        if current_actor
          result[:voted] = poll.voted_by?(current_actor)
          result[:own_votes] = poll.actor_choices(current_actor)
        end

        result
      end
    end
  end
end
