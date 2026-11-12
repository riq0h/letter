# frozen_string_literal: true

class ActivitiesController < ApplicationController
  include ActivityPubRequestHandling
  include ActivityPubObjectBuilding
  include ActivityDataBuilder

  skip_before_action :verify_authenticity_token
  before_action :set_activity
  before_action :ensure_activitypub_request

  # GET /activities/:id
  # ActivityPubアクティビティエンドポイント
  def show
    render json: build_activity_data(@activity),
           content_type: 'application/activity+json; charset=utf-8'
  end

  private

  def set_activity
    # IDからアクティビティを検索
    @activity = find_activity_by_id(params[:id])

    return if @activity && publicly_accessible_activity?(@activity)

    render json: { error: 'Activity not found' },
           status: :not_found,
           content_type: 'application/activity+json; charset=utf-8'
  end

  # このサーバのアクターのアクティビティで、対象投稿が非公開(フォロワー限定・DM)でないものだけ返す。
  # (以前は受信した他サーバのアクティビティや、DMのCreateまで返していた)
  def publicly_accessible_activity?(activity)
    return false unless activity.local? && activity.actor&.local?

    target = activity.object || activity.target_object
    return true unless target.is_a?(ActivityPubObject)

    target.publicly_accessible?
  end

  def find_activity_by_id(id)
    # フルap_idでの検索
    activity = Activity.find_by(ap_id: id)
    return activity if activity

    # IDでの直接検索
    Activity.find_by(id: id)
  end
end
