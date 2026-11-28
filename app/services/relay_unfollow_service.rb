# frozen_string_literal: true

# リレーの購読をやめる(承認待ちの申し込みの取り下げも含む)。リレーへUndo Followを送り、
# 届いたかどうかにかかわらず、こちらでは購読していない状態にする(Mastodonと同じ)
class RelayUnfollowService
  include RelayActorManagement

  def call(relay)
    @relay = relay
    @local_actor = local_actor
    return false unless @local_actor && (relay.accepted? || relay.pending?)

    undo_activity = create_undo_activity
    relay.update!(state: 'idle', follow_activity_id: nil, followed_at: nil, last_error: nil)

    result = deliver_activity(undo_activity, relay.inbox_url)
    relay.update!(last_error: "Undo Followを送れませんでした: #{result[:error]}") unless result[:success]
    true
  end

  private

  def create_undo_activity
    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{@local_actor.ap_id}#follows/relay/undo/#{SecureRandom.hex(16)}",
      'type' => 'Undo',
      'actor' => @local_actor.ap_id,
      'object' => {
        'id' => @relay.follow_activity_id,
        'type' => 'Follow',
        'actor' => @local_actor.ap_id,
        'object' => 'https://www.w3.org/ns/activitystreams#Public'
      },
      'to' => ['https://www.w3.org/ns/activitystreams#Public']
    }
  end
end
