# frozen_string_literal: true

module Api
  module V1
    class FiltersController < Api::BaseController
      include FilterSerializer

      before_action :doorkeeper_authorize!
      before_action :require_user!
      before_action :set_filter, only: %i[show update destroy]

      # GET /api/v1/filters
      def index
        filters = current_user.filters.active.recent
        render json: filters.map { |filter| serialized_filter(filter) }
      end

      # GET /api/v1/filters/:id
      def show
        render json: serialized_filter(@filter)
      end

      # POST /api/v1/filters
      def create
        filter = current_user.filters.build(filter_params)
        filter.context = params[:context] if params[:context].present?

        if filter.save
          # キーワードを追加
          if params[:keywords_attributes].present?
            params[:keywords_attributes].each do |keyword_params|
              filter.add_keyword!(keyword_params[:keyword], whole_word: keyword_params[:whole_word] == 'true')
            end
          end

          render json: serialized_filter(filter)
        else
          render_validation_error(filter)
        end
      end

      # PUT /api/v1/filters/:id
      def update
        if @filter.update(filter_params)
          @filter.context = params[:context] if params[:context].present?
          @filter.save if @filter.context_changed?

          # キーワードを更新
          if params[:keywords_attributes].present?
            @filter.filter_keywords.destroy_all
            params[:keywords_attributes].each do |keyword_params|
              @filter.add_keyword!(keyword_params[:keyword], whole_word: keyword_params[:whole_word] == 'true')
            end
          end

          render json: serialized_filter(@filter)
        else
          render_validation_error(@filter)
        end
      end

      # DELETE /api/v1/filters/:id
      def destroy
        @filter.destroy
        render json: {}
      end

      private

      def set_filter
        @filter = current_user.filters.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found('Filter')
      end

      def filter_params
        params.permit(:title, :expires_at, :filter_action)
      end
    end
  end
end
