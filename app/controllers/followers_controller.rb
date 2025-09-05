# frozen_string_literal: true

class FollowersController < ApplicationController
  include ErrorResponseHelper

  skip_before_action :verify_authenticity_token

  def show
    username = params[:username]
    @actor = Actor.find_by(username: username, local: true)

    unless @actor
      render_not_found('Actor')
      return
    end

    followers_collection = {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "#{activitypub_base_url}/users/#{@actor.username}/followers",
      'type' => 'OrderedCollection',
      'totalItems' => @actor.followers_count,
      'orderedItems' => [] # プライバシー保護のため詳細は非表示
    }

    render json: followers_collection, content_type: 'application/activity+json; charset=utf-8'
  end
end
