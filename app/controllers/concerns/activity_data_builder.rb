# frozen_string_literal: true

module ActivityDataBuilder
  extend ActiveSupport::Concern

  private

  def build_activity_data(activity)
    base_data = {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => activity.ap_id,
      'type' => activity.activity_type,
      'actor' => activity.actor.ap_id,
      'published' => activity.published_at.iso8601
    }

    # Activityタイプ別の詳細データ追加
    case activity.activity_type
    when 'Create'
      add_create_activity_data(base_data, activity)
    when 'Follow'
      add_follow_activity_data(base_data, activity)
    when 'Accept', 'Reject'
      add_response_activity_data(base_data, activity)
    when 'Announce'
      add_announce_activity_data(base_data, activity)
    when 'Like'
      add_like_activity_data(base_data, activity)
    when 'Delete'
      add_delete_activity_data(base_data, activity)
    when 'Update'
      add_update_activity_data(base_data, activity)
    when 'Undo'
      add_undo_activity_data(base_data, activity)
    else
      base_data
    end
  end

  def add_create_activity_data(base_data, activity)
    return base_data unless activity.object

    base_data.merge(
      'object' => activity.object.to_activitypub,
      'to' => build_activity_audience(activity.object, :to),
      'cc' => build_activity_audience(activity.object, :cc)
    )
  end

  def add_follow_activity_data(base_data, activity)
    base_data.merge('object' => activity.target_ap_id)
  end

  def add_response_activity_data(base_data, activity)
    base_data.merge('object' => activity.target_ap_id)
  end

  def add_announce_activity_data(base_data, activity)
    base_data.merge(
      'object' => activity.target_ap_id,
      'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      'cc' => [activity.actor.followers_url]
    )
  end

  def add_like_activity_data(base_data, activity)
    base_data.merge('object' => activity.target_ap_id)
  end

  def add_delete_activity_data(base_data, activity)
    base_data.merge('object' => activity.target_ap_id)
  end

  def add_update_activity_data(base_data, activity)
    return base_data unless activity.object

    base_data.merge(
      'object' => activity.object.to_activitypub,
      'to' => build_activity_audience(activity.object, :to),
      'cc' => build_activity_audience(activity.object, :cc)
    )
  end

  def add_undo_activity_data(base_data, activity)
    base_data.merge('object' => activity.target_ap_id)
  end
end
