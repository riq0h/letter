# frozen_string_literal: true

module Api
  module V1
    class PollsController < Api::BaseController
      include PollSerializer
      include ActivityDeliveryHelper

      before_action :doorkeeper_authorize!
      before_action :require_user!
      before_action :set_poll, only: %i[show vote]

      # GET /api/v1/polls/:id
      def show
        render json: serialize_poll_with_actor(@poll, current_user)
      end

      # POST /api/v1/polls/:id/votes
      def vote
        choices = parse_vote_choices

        if @poll.vote_for!(current_user, choices)
          send_vote_activities(choices) if @poll.remote_poll?
          render json: serialize_poll_with_actor(@poll, current_user)
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

      # リモート投票にVoteアクティビティを送信
      def send_vote_activities(choices)
        target_inbox = @poll.object.actor.inbox_url
        return if target_inbox.blank?

        choices.each do |choice_index|
          activity = Activity.create!(
            ap_id: ApIdGeneration.generate_ap_id,
            activity_type: 'Create',
            actor: current_user,
            target_ap_id: @poll.object.ap_id,
            published_at: Time.current,
            local: true,
            processed: true,
            raw_data: { vote_choice: choice_index, vote_name: @poll.option_titles[choice_index] }.to_json
          )

          enqueue_send_activity(activity, [target_inbox])
        end
      rescue StandardError => e
        Rails.logger.error "Failed to send vote activities: #{e.message}"
      end
    end
  end
end
