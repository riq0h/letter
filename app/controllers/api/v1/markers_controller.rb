# frozen_string_literal: true

module Api
  module V1
    class MarkersController < Api::BaseController
      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v1/markers
      def index
        timelines = params[:timeline] || %w[home notifications]
        timelines = [timelines] unless timelines.is_a?(Array)

        markers = {}

        timelines.each do |timeline|
          case timeline
          when 'home'
            markers['home'] = build_marker_response('home')
          when 'notifications'
            markers['notifications'] = build_marker_response('notifications')
          end
        end

        render json: markers
      end

      # POST /api/v1/markers
      def create
        markers = {}

        if params[:home] && params[:home][:last_read_id]
          save_marker('home', params[:home][:last_read_id])
          markers['home'] = build_marker_response('home')
        end

        if params[:notifications] && params[:notifications][:last_read_id]
          save_marker('notifications', params[:notifications][:last_read_id])
          markers['notifications'] = build_marker_response('notifications')
        end

        render json: markers
      end

      private

      def build_marker_response(timeline)
        marker = get_marker(timeline)
        return {} unless marker

        {
          last_read_id: marker.last_read_id.to_s,
          version: marker.version || 1,
          updated_at: marker.updated_at&.iso8601 || Time.current.iso8601
        }
      end

      def save_marker(timeline, last_read_id)
        marker = Marker.find_or_initialize_for_actor_and_timeline(current_user, timeline)
        marker.last_read_id = last_read_id

        if marker.new_record?
          marker.version = 1
        else
          marker.increment_version!
        end
        marker.save!
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.error "Failed to save marker for #{timeline}: #{e.message}"
        raise
      end

      def get_marker(timeline)
        current_user.markers.for_timeline(timeline).first
      end
    end
  end
end
