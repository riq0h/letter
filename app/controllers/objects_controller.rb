# frozen_string_literal: true

class ObjectsController < ApplicationController
  include ActivityPubRequestHandling

  skip_before_action :verify_authenticity_token
  before_action :set_object, only: %i[show likes shares]
  before_action :ensure_activitypub_request, only: [:show]

  # GET /users/:username/posts/:id
  # 配信(Create/Update)と同じ表現を返す。他サーバは引用の許可設定や、引用の承認の確認に
  # 取得したこの内容を使う
  def show
    render json: ActivityPubObjectSerializer.new(@object).to_activitypub,
           content_type: 'application/activity+json; charset=utf-8'
  end

  # GET /users/:username/posts/:id/likes, /shares
  # 投稿が名乗るlikes/sharesコレクション。Mastodonと同じく件数だけを返し、誰がしたかは載せない
  def likes
    render_count_collection("#{@object.ap_id}/likes", @object.favourites_count)
  end

  def shares
    render_count_collection("#{@object.ap_id}/shares", @object.reblogs_count)
  end

  private

  def render_count_collection(id, count)
    render json: {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => id,
      'type' => 'Collection',
      'totalItems' => count || 0
    }, content_type: 'application/activity+json; charset=utf-8'
  end

  def set_object
    # URLのユーザ名の投稿者が書いた、このサーバのオブジェクトのみを返す。
    # (以前はIDだけで検索しており、受信した他サーバの投稿まで返していた)
    actor = Actor.local.find_by(username: params[:username])
    scope = ActivityPubObject.where(actor: actor, local: true)
    id_param = params[:id].to_s

    @object = if id_param.match?(/^\d+$/)
                scope.find_by(id: id_param)
              else
                scope.find_by('ap_id LIKE ?', "%/posts/#{ActiveRecord::Base.sanitize_sql_like(id_param)}")
              end

    # 非公開投稿(フォロワー限定・DM)は存在を明かさず404
    return if actor && @object&.publicly_accessible?

    render json: { error: 'Object not found' }, status: :not_found
  end

  def ensure_activitypub_request
    super(status: :moved_permanently)
  end
end
