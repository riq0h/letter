# frozen_string_literal: true

class HomeController < ApplicationController
  include PaginationHelper
  include TimelineBuilder

  def index
    @posts = load_public_timeline
    @page_title = I18n.t('pages.home.title')

    setup_pagination

    return if params[:max_id].blank?

    sleep 0.5
    render partial: 'more_posts'
  end

  private

  def load_public_timeline
    posts = load_public_posts
    reblogs = load_public_reblogs
    timeline_items = build_timeline_items(posts, reblogs)
    apply_timeline_sorting_and_pagination(timeline_items)
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

  def apply_timeline_sorting_and_pagination(timeline_items)
    timeline_items.sort_by! { |item| -item[:published_at].to_i }
    timeline_items = apply_timeline_pagination_filters(timeline_items)
    timeline_items.take(30)
  end

  def apply_timeline_pagination_filters(timeline_items)
    return timeline_items if params[:max_id].blank?

    reference_time = extract_reference_time_from_max_id
    return timeline_items unless reference_time

    filter_timeline_items_by_time(timeline_items, reference_time)
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
