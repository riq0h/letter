# frozen_string_literal: true

class TagsController < ApplicationController
  include PaginationHelper
  include TimelineBuilder

  def show
    @tag = Tag.find_by(name: normalized_tag_name)

    unless @tag
      render 'errors/not_found', status: :not_found
      return
    end

    @posts = load_tag_timeline
    @page_title = "##{@tag.display_name.presence || @tag.name}"

    setup_pagination

    return if params[:max_id].blank?

    sleep 0.5
    render partial: 'more_posts'
  end

  private

  def normalized_tag_name
    params[:name].unicode_normalize(:nfkc).strip.downcase
  end

  def load_tag_timeline
    posts = load_tag_posts
    timeline_items = posts.map { |post| build_post_timeline_item(post) }
    apply_timeline_sorting_and_pagination(timeline_items)
  end

  def load_tag_posts
    ActivityPubObject.joins(:actor, :tags)
                     .where(tags: { id: @tag.id })
                     .where(visibility: 'public')
                     .includes(:actor, :media_attachments)
                     .order(published_at: :desc, id: :desc)
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

  def check_older_posts_available # rubocop:disable Naming/PredicateMethod
    return false unless @posts.any?

    last_item_time = @posts.last[:published_at]

    base_tag_query.exists?(['published_at < ?', last_item_time])
  end

  def base_tag_query
    ActivityPubObject.joins(:tags)
                     .where(tags: { id: @tag.id })
                     .where(visibility: 'public')
  end
end
