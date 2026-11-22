# frozen_string_literal: true

# 他サーバの相手からのフォロー(またはフォローリクエスト)を断ったことを、相手のサーバに伝える。
# 相手のサーバはこれを受けて、相手側のフォローを外す。フォローの記録は先に消してよいよう、
# 送るのに要る値だけを受け取る
class SendRejectFollowJob < ApplicationJob
  queue_as :default

  def perform(local_actor_id, follower_id, follow_activity_ap_id)
    local_actor = Actor.find_by(id: local_actor_id)
    follower = Actor.find_by(id: follower_id)
    return unless local_actor&.local? && follower && !follower.local?

    result = ActivitySender.new.send_activity(activity: payload(local_actor, follower, follow_activity_ap_id),
                                              target_inbox: follower.inbox_url, signing_actor: local_actor)
    Rails.logger.info "🚫 Reject Follow sent to #{follower.ap_id} (#{result[:success] ? 'ok' : result[:error]})"
  end

  private

  def payload(local_actor, follower, follow_activity_ap_id)
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{local_actor.ap_id}#rejects/follows/#{SecureRandom.hex(8)}",
      'type' => 'Reject',
      'actor' => local_actor.ap_id,
      'object' => {
        'id' => follow_activity_ap_id,
        'type' => 'Follow',
        'actor' => follower.ap_id,
        'object' => local_actor.ap_id
      }
    }
  end
end
