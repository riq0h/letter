# frozen_string_literal: true

module NotificationHelper
  extend ActiveSupport::Concern

  private

  def status_notification?(notification)
    %w[mention reblog favourite status update poll quote].include?(notification.notification_type)
  end

  def preload_activity_pub_objects(notifications)
    object_ids = notifications.filter_map do |notification|
      notification.activity_id if notification.activity_type == 'ActivityPubObject'
    end

    return {} if object_ids.empty?

    ActivityPubObject.where(id: object_ids)
                     .includes(:actor, :media_attachments)
                     .index_by(&:id)
  end

  def notification_limit_param
    [params.fetch(:limit, 40).to_i, 80].min
  end

  def apply_notification_pagination(notifications)
    max_id = params[:max_id] || params[:maxId]
    since_id = params[:since_id] || params[:sinceId]
    min_id = params[:min_id] || params[:minId]

    notifications = notifications.where(notifications: { id: ...max_id }) if max_id.present?
    notifications = notifications.where('notifications.id > ?', since_id) if since_id.present?
    notifications = notifications.where('notifications.id > ?', min_id) if min_id.present?
    notifications
  end

  def add_notification_pagination_headers(notifications, url_method)
    return if notifications.empty?

    links = []
    newest_id = notifications.first.id
    oldest_id = notifications.last.id

    if notifications.count >= notification_limit_param
      next_url = send(url_method, max_id: oldest_id, limit: notification_limit_param)
      next_url += "&exclude_types[]=#{params[:exclude_types].join('&exclude_types[]=')}" if params[:exclude_types].present?
      links << "<#{next_url}>; rel=\"next\""
    end

    if params[:max_id].present?
      prev_url = send(url_method, min_id: newest_id, limit: notification_limit_param)
      prev_url += "&exclude_types[]=#{params[:exclude_types].join('&exclude_types[]=')}" if params[:exclude_types].present?
      links << "<#{prev_url}>; rel=\"prev\""
    end

    response.headers['Link'] = links.join(', ') if links.any?
  end
end
