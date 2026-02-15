# frozen_string_literal: true

class RelayUnfollowService
  include ActivityPubHelper
  include RelayActorManagement

  def call(relay)
    @relay = relay
    @local_actor = local_actor

    return false unless @local_actor && @relay&.accepted?

    begin
      # リレーアクターの情報を取得
      relay_actor_data = fetch_activitypub_object(@relay.actor_uri)
      return false unless relay_actor_data

      # Undo Follow アクティビティを作成
      undo_activity = create_undo_activity(relay_actor_data)

      # Undo アクティビティを送信
      success = deliver_activity(undo_activity, @relay.inbox_url)

      if success
        @relay.update!(
          state: 'idle',
          follow_activity_id: nil,
          followed_at: nil,
          last_error: nil
        )
        true
      else
        @relay.update!(last_error: 'Undo Follow アクティビティの送信に失敗しました')
        false
      end
    rescue StandardError => e
      Rails.logger.error "Relay unfollow error: #{e.message}"
      @relay.update!(last_error: e.message)
      false
    end
  end

  private

  def create_undo_activity(_relay_actor_data)
    undo_id = "#{@local_actor.ap_id}#follows/relay/undo/#{SecureRandom.hex(16)}"

    # 元のFollow アクティビティを再構築
    original_follow = {
      'id' => @relay.follow_activity_id,
      'type' => 'Follow',
      'actor' => @local_actor.ap_id,
      'object' => 'https://www.w3.org/ns/activitystreams#Public'
    }

    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => undo_id,
      'type' => 'Undo',
      'actor' => @local_actor.ap_id,
      'object' => original_follow,
      'to' => ['https://www.w3.org/ns/activitystreams#Public'],
      'cc' => []
    }
  end
end
