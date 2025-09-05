# frozen_string_literal: true

class ProfilesController < ApplicationController
  include StatusSerializer
  include PaginationHelper
  include TimelineBuilder
  before_action :find_actor, except: [:redirect_to_frontend]

  def show
    return render_activitypub_profile if activitypub_request?

    @current_tab = params[:tab] || 'posts'
    @posts = load_posts_for_tab(@current_tab)
    setup_pagination

    if params[:max_id].present?
      sleep 0.5
      render partial: 'more_posts'
    end

    # フォロー・フォロワー数
    @followers_count = @actor.followers_count
    @following_count = @actor.following_count
    @posts_count = @actor.posts_count
  end

  # GET /users/{username}
  # ActivityPubリクエストかフロントエンドリダイレクトかを判定
  def redirect_to_frontend
    username = params[:username]

    # ActivityPubクライアントの場合はJSONレスポンスを返す
    if activitypub_client_request?
      render_activitypub_profile_by_username(username)
    else
      # ブラウザアクセスの場合はフロントエンドにリダイレクト
      redirect_to profile_path(username: username), status: :moved_permanently
    end
  end

  private

  # ActivityPubクライアントからのリクエストかどうかを判定（PostsControllerと同じロジック）
  def activitypub_client_request?
    # Accept headerでActivityPubリクエストを判定
    accept_header = request.headers['Accept'] || ''
    accept_header.include?('application/activity+json') ||
      accept_header.include?('application/ld+json') ||
      accept_header.include?('application/json')
  end

  def render_activitypub_profile
    render json: @actor.to_activitypub(request),
           content_type: 'application/activity+json; charset=utf-8'
  end

  def render_activitypub_profile_by_username(username)
    actor = Actor.local.find_by(username: username)
    unless actor
      render json: { error: 'Actor not found' }, status: :not_found
      return
    end

    render json: actor.to_activitypub(request),
           content_type: 'application/activity+json; charset=utf-8'
  end

  def load_posts_for_tab(tab)
    case tab
    when 'media'
      load_user_media_posts
    else
      load_user_posts
    end
  end

  def find_actor
    username = params[:username]
    @actor = Actor.find_by(username: username, local: true)

    unless @actor
      render 'errors/not_found', status: :not_found
      return
    end

    # 凍結されたアカウントのチェック
    return unless @actor.suspended?

    render 'errors/suspended', status: :forbidden
    nil
  end

  def load_user_posts
    posts = load_user_post_objects
    reblogs = load_user_reblog_objects
    pinned_posts = load_pinned_posts
    timeline_items = build_user_timeline_items(posts, reblogs, pinned_posts)
    apply_user_timeline_sorting_and_pagination(timeline_items)
  end

  def load_user_post_objects
    ActivityPubObject
      .joins(:actor)
      .where(actor: @actor)
      .where(visibility: %w[public unlisted])
      .where(object_type: 'Note')
      .where(local: true)
      .includes(:actor)
  end

  def load_user_reblog_objects
    Reblog.joins(:actor, :object)
          .where(actor: @actor)
          .where(objects: { visibility: %w[public unlisted] })
          .includes(:actor, object: %i[actor media_attachments])
  end

  def build_user_timeline_items(posts, reblogs, pinned_posts)
    # Pinned postsを先に追加（最上部に表示）
    timeline_items = pinned_posts.map do |pinned_status|
      build_pinned_timeline_item(pinned_status.object)
    end

    posts.find_each do |post|
      # Pinned postsも元の時系列位置に表示するため、重複除外は行わない
      timeline_items << build_post_timeline_item(post)
    end

    reblogs.find_each do |reblog|
      timeline_items << build_reblog_timeline_item(reblog)
    end

    timeline_items
  end

  def load_pinned_posts
    @actor.pinned_statuses
          .includes(object: %i[actor media_attachments mentions tags])
          .ordered
  end

  def apply_user_timeline_sorting_and_pagination(timeline_items)
    # Pinned statusとその他を分離
    pinned_items = timeline_items.select { |item| item[:type] == :pinned_post }
    other_items = timeline_items.reject { |item| item[:type] == :pinned_post }

    # その他の投稿のみを時刻順でソート
    other_items.sort_by! { |item| -item[:published_at].to_i }

    # Pinned statusを最上部に、その後にその他の投稿を配置
    sorted_items = pinned_items + other_items

    # ページネーション処理
    sorted_items = apply_timeline_pagination_filters(sorted_items)
    sorted_items.take(30)
  end

  def load_user_media_posts
    query = ActivityPubObject
            .joins(:actor)
            .joins(:media_attachments)
            .where(actor: @actor)
            .where(visibility: %w[public unlisted])
            .where(object_type: 'Note')
            .where(local: true)
            .includes(:actor, :media_attachments)
            .order(published_at: :desc)
            .distinct

    posts = apply_pagination_filters(query).limit(30)

    # タイムライン形式に変換
    posts.map { |post| build_post_timeline_item(post) }
  end

  def apply_timeline_pagination_filters(timeline_items)
    return timeline_items if params[:max_id].blank?

    reference_time = extract_profiles_reference_time_from_max_id
    return timeline_items unless reference_time

    filter_profiles_timeline_items_by_time(timeline_items, reference_time)
  end

  def extract_profiles_reference_time_from_max_id
    max_id = params[:max_id]

    if max_id.start_with?('post_')
      extract_profiles_post_reference_time(max_id)
    elsif max_id.start_with?('reblog_')
      extract_profiles_reblog_reference_time(max_id)
    end
  end

  def extract_profiles_post_reference_time(max_id)
    post_id = max_id.sub('post_', '')
    reference_post = ActivityPubObject.find_by(id: post_id)
    reference_post&.published_at
  end

  def extract_profiles_reblog_reference_time(max_id)
    reblog_id = max_id.sub('reblog_', '')
    reference_reblog = Reblog.find_by(id: reblog_id)
    reference_reblog&.created_at
  end

  def filter_profiles_timeline_items_by_time(timeline_items, reference_time)
    timeline_items.select { |item| item[:published_at] < reference_time }
  end

  def find_post_by_id(id)
    numeric_id = id.to_s.start_with?('post_') ? id.sub('post_', '') : id
    ActivityPubObject.find_by(id: numeric_id)
  end

  def get_post_display_id(timeline_item)
    timeline_item[:id]
  end

  def check_older_posts_available
    return false unless @posts.any?

    # タイムライン形式の場合（mediaタブも含む）
    last_item_time = @posts.last[:published_at]

    if @current_tab == 'media'
      base_query = base_media_query
      base_query.exists?(['published_at < ?', last_item_time])
    else
      # より古い投稿またはリポストがあるかチェック
      older_posts_exist = base_posts_query.exists?(['published_at < ?', last_item_time])
      older_reblogs_exist = Reblog.joins(:actor, :object)
                                  .where(actor: @actor)
                                  .where(objects: { visibility: %w[public unlisted] })
                                  .exists?(['reblogs.created_at < ?', last_item_time])

      older_posts_exist || older_reblogs_exist
    end
  end

  def base_posts_query
    ActivityPubObject
      .joins(:actor)
      .where(actor: @actor)
      .where(visibility: %w[public unlisted])
      .where(object_type: 'Note')
      .where(local: true)
  end

  def base_media_query
    ActivityPubObject
      .joins(:actor)
      .joins(:media_attachments)
      .where(actor: @actor)
      .where(visibility: %w[public unlisted])
      .where(object_type: 'Note')
      .where(local: true)
      .distinct
  end
end
