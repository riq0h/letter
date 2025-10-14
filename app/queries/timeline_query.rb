# frozen_string_literal: true

class TimelineQuery
  def initialize(user, params = {})
    @user = user
    @params = params
  end

  def build_home_timeline
    followed_ids = user.followed_actors.pluck(:id) + [user.id]

    statuses = base_timeline_query.where(actors: { id: followed_ids })
    statuses = apply_pagination_filters(statuses).limit(limit * 10)

    reblogs = fetch_reblogs(followed_ids)

    MergedTimeline.merge(statuses, reblogs, limit * 2).to_a
  end

  def build_public_timeline
    statuses = base_timeline_query.where(visibility: 'public')
    statuses = statuses.where(actors: { local: true }) if local_only?
    apply_pagination_filters(statuses).limit(limit)
  end

  def build_hashtag_timeline(hashtag_name)
    tag = Tag.find_by(name: hashtag_name)
    return ActivityPubObject.none unless tag

    statuses = base_timeline_query
               .joins(:tags)
               .where(tags: { id: tag.id })
               .where(visibility: 'public')
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
    apply_reblog_pagination_filters(reblogs).limit(limit * 10)
  end

  def apply_pagination_filters(query)
    query = query.where(objects: { id: ...(params[:max_id]) }) if params[:max_id].present?
    query = query.where('objects.id > ?', params[:since_id]) if params[:since_id].present? && params[:min_id].blank?
    query = query.where('objects.id > ?', params[:min_id]) if params[:min_id].present?
    query
  end

  def apply_reblog_pagination_filters(query)
    query = query.where(reblogs: { object_id: ...(params[:max_id]) }) if params[:max_id].present?

    query = query.where('reblogs.object_id > ?', params[:since_id]) if params[:since_id].present? && params[:min_id].blank?

    query = query.where('reblogs.object_id > ?', params[:min_id]) if params[:min_id].present?

    query
  end
end
