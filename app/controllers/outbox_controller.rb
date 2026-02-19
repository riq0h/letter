# frozen_string_literal: true

class OutboxController < ApplicationController
  include ActivityPubBlockerControl
  include ActivityPubRequestHandling
  include ActivityPubObjectBuilding
  include ActivityDataBuilder
  include ErrorResponseHelper

  PAGE_SIZE = 20
  AP_CONTENT_TYPE = 'application/activity+json; charset=utf-8'

  skip_before_action :verify_authenticity_token
  before_action :set_actor
  before_action :ensure_activitypub_request
  before_action :check_if_blocked_by_target, if: -> { activitypub_request? }

  # GET /users/:username/outbox
  # ActivityPub Outbox Collection を返す
  def show
    if params[:page].present?
      render_collection_page
    else
      render_collection_summary
    end
  end

  private

  def set_actor
    username = params[:username]
    @actor = Actor.find_by(username: username, local: true)

    return if @actor

    render_not_found('Actor')
  end

  def render_collection_summary
    total = outbox_base_query.count

    render json: {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => @actor.outbox_url,
      'type' => 'OrderedCollection',
      'totalItems' => total,
      'first' => "#{@actor.outbox_url}?page=true",
      'last' => "#{@actor.outbox_url}?page=true&min_id=0"
    }, content_type: AP_CONTENT_TYPE
  end

  def render_collection_page
    activities = fetch_paginated_activities

    render json: build_collection_page(activities),
           content_type: AP_CONTENT_TYPE
  end

  def outbox_base_query
    Activity.joins(:actor, :object)
            .where(actors: { id: @actor.id })
            .where(local: true, activity_type: 'Create')
            .where(objects: { visibility: %w[public unlisted] })
  end

  def fetch_paginated_activities
    query = outbox_base_query.includes(:object, :actor)
    query = query.where(Activity.arel_table[:id].lt(params[:max_id])) if params[:max_id].present?
    query = query.where(Activity.arel_table[:id].gt(params[:min_id])) if params[:min_id].present?
    query.order(id: :desc).limit(PAGE_SIZE)
  end

  def build_collection_page(activities)
    page = {
      '@context' => Rails.application.config.activitypub.context_url,
      'type' => 'OrderedCollectionPage',
      'id' => current_page_url,
      'partOf' => @actor.outbox_url,
      'orderedItems' => activities.map { |activity| build_activity_data(activity) }
    }

    page['next'] = "#{@actor.outbox_url}?page=true&max_id=#{activities.last.id}" if activities.size == PAGE_SIZE
    page['prev'] = "#{@actor.outbox_url}?page=true&min_id=#{activities.first.id}" if params[:max_id].present? || params[:min_id].present?

    page
  end

  def current_page_url
    url = "#{@actor.outbox_url}?page=true"
    url += "&max_id=#{params[:max_id]}" if params[:max_id].present?
    url += "&min_id=#{params[:min_id]}" if params[:min_id].present?
    url
  end
end
