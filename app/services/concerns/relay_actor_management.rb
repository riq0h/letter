# frozen_string_literal: true

module RelayActorManagement
  extend ActiveSupport::Concern

  private

  def local_actor
    # ローカルの管理者アカウントを取得
    actor = Actor.where(local: true, admin: true).first || Actor.where(local: true).first

    # ap_idが設定されていない場合は設定
    if actor && actor.ap_id.blank?
      actor.send(:set_ap_urls)
      actor.save!
    end

    actor
  end

  def deliver_activity(activity, inbox_url)
    activity_sender = ActivitySender.new
    activity_sender.send_activity(
      activity: activity,
      target_inbox: inbox_url,
      signing_actor: @local_actor
    )
  rescue StandardError => e
    Rails.logger.error "Failed to deliver activity: #{e.message}"
    { success: false, error: e.message }
  end
end
