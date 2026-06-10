# frozen_string_literal: true

class HomeController < ApplicationController
  include PaginationHelper
  include TimelineBuilder

  PAGE_SIZE = 30

  def index
    @posts = load_public_timeline
    @page_title = I18n.t('pages.home.title')

    setup_pagination

    return if params[:max_id].blank?

    render partial: 'more_posts'
  end

  private

  def load_public_timeline
    # ページネーション・件数制限はSQL側で行う
    # （全ローカル投稿をロードしてRubyでソートすると投稿数に比例して遅くなる）
    reference_time = params[:max_id].present? ? extract_reference_time_from_max_id : nil

    posts = load_public_posts
    reblogs = load_public_reblogs
    if reference_time
      posts = posts.where(published_at: ...reference_time)
      reblogs = reblogs.where(created_at: ...reference_time)
    end

    timeline_items = build_timeline_items(posts.limit(PAGE_SIZE), reblogs.limit(PAGE_SIZE))
    timeline_items.sort_by! { |item| -item[:published_at].to_i }
    timeline_items.take(PAGE_SIZE)
  end

  def load_public_posts
    ActivityPubObject.joins(:actor)
                     .where(actors: { local: true })
                     .where(visibility: %w[public unlisted])
                     .where(local: true)
                     .includes(:actor, :media_attachments)
                     .order(published_at: :desc, id: :desc)
  end

  def load_public_reblogs
    Reblog.joins(:actor, :object)
          .where(actors: { local: true })
          .where(objects: { visibility: %w[public unlisted] })
          .includes(:actor, object: %i[actor media_attachments])
          .order(created_at: :desc, id: :desc)
  end

  def build_timeline_items(posts, reblogs)
    build_timeline_items_from_posts_and_reblogs(posts, reblogs)
  end

  def find_post_by_id(id)
    ActivityPubObject.find_by(id: id)
  end

  def check_older_posts_available
    return false unless @posts.any?

    last_item_time = @posts.last[:published_at]

    # より古い投稿またはリポストがあるかチェック
    older_posts_exist = base_query.exists?(['published_at < ?', last_item_time])
    older_reblogs_exist = Reblog.joins(:actor, :object)
                                .where(actors: { local: true })
                                .where(objects: { visibility: %w[public unlisted] })
                                .exists?(['reblogs.created_at < ?', last_item_time])

    older_posts_exist || older_reblogs_exist
  end

  def base_query
    ActivityPubObject.joins(:actor)
                     .where(actors: { local: true })
                     .where(visibility: %w[public unlisted])
                     .where(local: true)
  end
end
