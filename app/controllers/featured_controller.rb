# frozen_string_literal: true

class FeaturedController < ApplicationController
  include ErrorResponseHelper

  def show
    username = params[:username]
    @actor = Actor.find_by(username: username, local: true)

    unless @actor
      render_not_found('Actor')
      return
    end

    # Featured collection（ピン留め投稿）
    pinned_statuses = @actor.pinned_statuses
                            .includes(object: [:actor])
                            .ordered
                            .map(&:object)

    ordered_items = pinned_statuses.map do |status|
      activitypub_data = status.to_activitypub
      activitypub_data.except('@context')
    end

    featured_collection = {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "#{activitypub_base_url}/users/#{@actor.username}/collections/featured",
      'type' => 'OrderedCollection',
      'totalItems' => ordered_items.size,
      'orderedItems' => ordered_items
    }

    render json: featured_collection, content_type: 'application/activity+json; charset=utf-8'
  end
end
