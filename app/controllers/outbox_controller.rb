# frozen_string_literal: true

class OutboxController < ApplicationController
  include ActivityPubBlockerControl
  include ActivityPubRequestHandling
  include ActivityPubObjectBuilding
  include ActivityDataBuilder
  include ErrorResponseHelper

  skip_before_action :verify_authenticity_token
  before_action :set_actor
  before_action :ensure_activitypub_request
  before_action :check_if_blocked_by_target, if: -> { activitypub_request? }

  # GET /users/:username/outbox
  # ActivityPub Outbox Collection を返す
  def show
    outbox_data = build_outbox_collection(@actor)

    render json: outbox_data,
           content_type: 'application/activity+json; charset=utf-8'
  end

  private

  def set_actor
    username = params[:username]
    @actor = Actor.find_by(username: username, local: true)

    return if @actor

    render_not_found('Actor')
  end

  def build_outbox_collection(actor)
    activities = fetch_outbox_activities(actor)

    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => actor.outbox_url,
      'type' => 'OrderedCollection',
      'totalItems' => activities.count,
      'first' => build_first_page(actor, activities)
    }
  end

  def fetch_outbox_activities(actor)
    # ローカルアクターの公開アクティビティを取得
    Activity.joins(:actor)
            .where(actors: { id: actor.id })
            .where(local: true)
            .includes(:object, :actor)
            .order(published_at: :desc)
            .limit(20)
  end

  def build_first_page(actor, activities)
    {
      'type' => 'OrderedCollectionPage',
      'id' => "#{actor.outbox_url}?page=1",
      'partOf' => actor.outbox_url,
      'orderedItems' => activities.map { |activity| build_activity_data(activity) }
    }
  end
end
