# frozen_string_literal: true

module TimelineBuilder
  extend ActiveSupport::Concern

  private

  def setup_pagination
    setup_max_id_pagination
  end

  def apply_pagination_filters(query)
    if params[:max_id].present?
      reference_post = find_post_by_id(params[:max_id])
      query = query.where(published_at: ...reference_post.published_at) if reference_post
    end
    query
  end

  def build_post_timeline_item(post)
    {
      type: :post,
      item: post,
      published_at: post.published_at,
      id: "post_#{post.id}"
    }
  end

  def build_reblog_timeline_item(reblog)
    {
      type: :reblog,
      item: reblog,
      published_at: reblog.created_at,
      id: "reblog_#{reblog.id}"
    }
  end

  def build_pinned_timeline_item(post)
    {
      type: :pinned_post,
      item: post,
      published_at: post.published_at,
      id: "pinned_#{post.id}"
    }
  end

  def extract_reference_time_from_max_id
    max_id = params[:max_id]

    if max_id.start_with?('post_')
      post_id = max_id.sub('post_', '')
      ActivityPubObject.find_by(id: post_id)&.published_at
    elsif max_id.start_with?('reblog_')
      reblog_id = max_id.sub('reblog_', '')
      Reblog.find_by(id: reblog_id)&.created_at
    end
  end

  def filter_timeline_items_by_time(timeline_items, reference_time)
    timeline_items.select { |item| item[:published_at] < reference_time }
  end

  def get_post_display_id(timeline_item)
    timeline_item[:id]
  end

  def build_timeline_items_from_posts_and_reblogs(posts, reblogs)
    timeline_items = posts.map do |post|
      build_post_timeline_item(post)
    end

    reblogs.each do |reblog|
      timeline_items << build_reblog_timeline_item(reblog)
    end

    timeline_items
  end
end
