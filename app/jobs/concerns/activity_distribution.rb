# frozen_string_literal: true

# フォロワーへのActivityPub配信ロジックを共通化するconcern
module ActivityDistribution
  extend ActiveSupport::Concern

  private

  def distribute_activity(activity, actor)
    follower_inboxes = actor.followers.where(local: false).pluck(:shared_inbox_url, :inbox_url)
                            .filter_map { |shared, inbox| shared.presence || inbox }
                            .uniq

    follower_inboxes.each do |inbox_url|
      send_activity_to_inbox(activity, inbox_url, actor)
    end
  end

  def send_activity_to_inbox(activity, inbox_url, actor)
    activity_sender = ActivitySender.new

    result = activity_sender.send_activity(
      activity: activity,
      target_inbox: inbox_url,
      signing_actor: actor
    )

    result[:success]
  rescue StandardError => e
    Rails.logger.error "💥 Error sending #{activity['type']} activity to #{inbox_url}: #{e.message}"
    false
  end
end
