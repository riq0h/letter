# frozen_string_literal: true

module Api
  module V1
    class ScheduledStatusesController < Api::BaseController
      before_action :doorkeeper_authorize!
      before_action :require_user!
      before_action :set_scheduled_status, only: %i[show update destroy]

      # GET /api/v1/scheduled_statuses
      def index
        limit = [params.fetch(:limit, 20).to_i, 40].min

        scheduled_statuses = current_user.scheduled_statuses
                                         .pending
                                         .order(scheduled_at: :asc)
                                         .limit(limit)

        scheduled_statuses = scheduled_statuses.where(id: ...(params[:max_id])) if params[:max_id].present?

        scheduled_statuses = scheduled_statuses.where('id > ?', params[:min_id]) if params[:min_id].present?

        render json: scheduled_statuses.map(&:to_mastodon_api)
      end

      # GET /api/v1/scheduled_statuses/:id
      def show
        render json: @scheduled_status.to_mastodon_api
      end

      # PUT /api/v1/scheduled_statuses/:id
      def update
        begin
          new_scheduled_at = Time.zone.parse(params[:scheduled_at])
        rescue ArgumentError, TypeError
          render_validation_failed('Invalid scheduled_at format')
          return
        end

        if @scheduled_status.update(scheduled_at: new_scheduled_at)
          render json: @scheduled_status.to_mastodon_api
        else
          render json: {
            error: @scheduled_status.errors.full_messages.join(', ')
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/scheduled_statuses/:id
      def destroy
        @scheduled_status.destroy!
        head :ok
      end

      private

      def set_scheduled_status
        @scheduled_status = current_user.scheduled_statuses.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Scheduled status')
      end
    end
  end
end
