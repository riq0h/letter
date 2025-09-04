# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :set_post, only: [:show_html]

  # GET /users/{username}/posts/{id}
  # ActivityPubリクエストかフロントエンドリダイレクトかを判定
  def redirect_to_frontend
    username = params[:username]
    id = params[:id]

    # ActivityPubクライアントの場合はJSONレスポンスを返す
    if activitypub_request?
      render_activitypub_object(username, id)
    else
      # ブラウザアクセスの場合はフロントエンドにリダイレクト
      redirect_to post_html_path(username: username, id: id), status: :moved_permanently
    end
  end

  # GET /@{username}/{id}
  # HTML表示用
  def show_html
    @actor = @post.actor
    @media_attachments = @post.media_attachments.includes(:actor)

    setup_meta_tags
  end

  private

  def activitypub_request?
    # Accept headerでActivityPubリクエストを判定
    accept_header = request.headers['Accept'] || ''
    accept_header.include?('application/activity+json') ||
      accept_header.include?('application/ld+json') ||
      accept_header.include?('application/json')
  end

  def render_activitypub_object(username, id)
    actor = Actor.local.find_by(username: username)
    unless actor
      render json: { error: 'Actor not found' }, status: :not_found
      return
    end

    object = ActivityPubObject.where(actor: actor)
                              .where(local: true)
                              .find_by(id: id)
    unless object
      render json: { error: 'Object not found' }, status: :not_found
      return
    end

    # ActivityPubObjectSerializerを使用してシリアライズ
    serialized = ActivityPubObjectSerializer.new(object).to_activitypub
    render json: serialized, content_type: 'application/activity+json'
  end

  def setup_meta_tags
    title = truncate(@post.content_plaintext, length: 60)
    description = truncate(@post.content_plaintext, length: 160)

    configure_meta_tags(title, description)
  end

  def configure_meta_tags(title, description)
    image_url = @post.media_attachments.first&.url || @actor.avatar_url

    @meta_tags = {
      title: title,
      description: description,
      og: build_og_tags(description, image_url),
      twitter: build_twitter_tags(description, image_url)
    }
  end

  def build_og_tags(description, image_url)
    {
      title: "#{@actor.display_name} (@#{@actor.username})",
      description: description,
      type: 'article',
      url: @post.public_url,
      image: image_url
    }
  end

  def build_twitter_tags(description, image_url)
    {
      card: @post.media_attachments.any? ? 'summary_large_image' : 'summary',
      title: "#{@actor.display_name} (@#{@actor.username})",
      description: description,
      image: image_url
    }
  end

  def set_post
    username = params[:username]
    id_param = params[:id]

    actor = find_actor(username)
    return unless actor

    @post = find_post(actor, id_param)
    render_not_found unless @post
  end

  def find_actor(username)
    actor = Actor.local.find_by(username: username)
    render_not_found unless actor
    actor
  end

  def find_post(actor, id_param)
    # ローカル投稿のみ対象
    ActivityPubObject.where(actor: actor)
                     .where(local: true)
                     .find_by(id: id_param)
  end

  def render_not_found
    render plain: 'Not Found', status: :not_found
  end

  attr_writer :meta_tags

  def truncate(text, options = {})
    return '' if text.blank?

    length = options[:length] || 30
    text.length > length ? "#{text[0...length]}..." : text
  end
end
