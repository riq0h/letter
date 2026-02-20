# frozen_string_literal: true

class TimelineQuery
  def initialize(user, params = {})
    @user = user
    @params = params
  end

  def build_home_timeline
    followed_ids = user.followed_actors.pluck(:id) + [user.id]

    statuses = base_timeline_query.where(actors: { id: followed_ids })

    # フォロー中タグの投稿を追加
    followed_tag_ids = user.followed_tags.pluck(:tag_id)
    if followed_tag_ids.any?
      tag_object_ids = ObjectTag.where(tag_id: followed_tag_ids)
                                .joins(object: :actor)
                                .where(objects: { visibility: 'public', object_type: %w[Note Question] })
                                .pluck(:object_id)
      statuses = statuses.or(base_timeline_query.where(objects: { id: tag_object_ids })) if tag_object_ids.any?
    end

    statuses = apply_pagination_filters(statuses).limit(limit * 5)

    reblogs = fetch_reblogs(followed_ids)

    MergedTimeline.merge(statuses, reblogs, limit).to_a
  end

  def build_public_timeline
    statuses = base_timeline_query.where(visibility: 'public')
    statuses = statuses.where(actors: { local: true }) if local_only?
    apply_pagination_filters(statuses).limit(limit)
  end

  def build_hashtag_timeline(hashtag_name)
    normalized_name = hashtag_name.unicode_normalize(:nfkc).strip.downcase
    tag = Tag.find_by(name: normalized_name)
    return ActivityPubObject.none unless tag

    statuses = base_timeline_query
               .joins(:tags)
               .where(tags: { id: tag.id })
               .where(visibility: 'public')
    apply_pagination_filters(statuses).limit(limit)
  end

  def build_list_timeline(list)
    member_ids = list.list_memberships.pluck(:actor_id)
    return ActivityPubObject.none if member_ids.empty?

    statuses = base_timeline_query.where(actors: { id: member_ids })
    apply_pagination_filters(statuses).limit(limit)
  end

  private

  attr_reader :user, :params

  def limit
    params[:limit] || 20
  end

  def local_only?
    params[:local].present? && params[:local] != 'false'
  end

  def base_timeline_query
    query = ActivityPubObject.joins(:actor)
                             .includes(:actor, :media_attachments, :poll)
                             .where(object_type: %w[Note Question])
                             .where(is_pinned_only: false)
                             .order('objects.id DESC')

    query = UserTimelineQuery.new(user).apply(query) if user
    query
  end

  def fetch_reblogs(followed_ids)
    reblogs = Reblog.joins(:actor, :object)
                    .where(actor_id: followed_ids)
                    .where(objects: { visibility: %w[public unlisted] })
                    .includes(object: %i[actor media_attachments poll], actor: {})
                    .order('reblogs.created_at DESC')
    apply_reblog_pagination_filters(reblogs).limit(limit * 5)
  end

  def apply_pagination_filters(query)
    query = query.where(objects: { id: ...(params[:max_id]) }) if params[:max_id].present?
    query = query.where('objects.id > ?', params[:since_id]) if params[:since_id].present? && params[:min_id].blank?
    query = query.where('objects.id > ?', params[:min_id]) if params[:min_id].present?
    query
  end

  def apply_reblog_pagination_filters(query)
    if params[:max_id].present?
      max_time = snowflake_to_time(params[:max_id])
      query = query.where(reblogs: { created_at: ...max_time }) if max_time
    end
    if params[:since_id].present? && params[:min_id].blank?
      since_time = snowflake_to_time(params[:since_id])
      query = query.where('reblogs.created_at > ?', since_time) if since_time
    end
    if params[:min_id].present?
      min_time = snowflake_to_time(params[:min_id])
      query = query.where('reblogs.created_at > ?', min_time) if min_time
    end
    query
  end

  def snowflake_to_time(id)
    return nil if id.blank?

    Letter::Snowflake.extract_timestamp(id)
  rescue ArgumentError, RangeError
    nil
  end
end
