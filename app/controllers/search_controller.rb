# frozen_string_literal: true

class SearchController < ApplicationController
  include PaginationHelper
  def index
    initialize_search_params
    return if @query.blank?

    perform_search
    setup_pagination
    render_partial_if_needed
  end

  private

  def initialize_search_params
    @query = params[:q]&.strip
    @username = params[:username]
    @posts = []
  end

  def perform_search
    search_service = create_search_service

    @posts = if @username.present?
               search_user_posts(search_service)
             else
               search_service.search
             end
  end

  def create_search_service
    SearchQuery.new(
      query: @query,
      limit: 30,
      offset: params[:offset].to_i
    )
  end

  def search_user_posts(search_service)
    actor = Actor.find_by(username: @username, local: true)
    return [] unless actor

    search_service.user_posts_search(actor.id)
  end

  def setup_pagination
    setup_offset_pagination(30)
  end

  def render_partial_if_needed
    return if params[:offset].blank?

    sleep 0.5
    render partial: 'more_posts'
    nil
  end
end
