# frozen_string_literal: true

class RelayFollowService
  include ActivityPubHelper
  include RelayActorManagement

  def call(relay)
    @relay = relay
    @local_actor = local_actor

    return false unless @local_actor && @relay&.idle?

    begin
      # リレーアクターの情報を取得
      relay_actor_data = fetch_activitypub_object(@relay.actor_uri)
      
      unless relay_actor_data
        error_msg = "リレーアクター情報の取得に失敗しました: #{@relay.actor_uri}"
        Rails.logger.error error_msg
        @relay.update!(last_error: error_msg)
        return false
      end

      # Follow アクティビティを作成
      follow_activity = create_follow_activity(relay_actor_data)

      # Follow アクティビティを送信
      result = deliver_activity(follow_activity, @relay.inbox_url)

      if result && result[:success]
        @relay.update!(
          state: 'pending',
          follow_activity_id: follow_activity['id'],
          followed_at: Time.current,
          last_error: nil
        )
        true
      else
        error_msg = result ? result[:error] : 'Follow アクティビティの送信に失敗しました'
        @relay.update!(last_error: error_msg)
        false
      end
    rescue StandardError => e
      Rails.logger.error "Relay follow error: #{e.message}"
      @relay.update!(last_error: e.message)
      false
    end
  end

  private

  def create_follow_activity(_relay_actor_data)
    activity_id = "#{@local_actor.ap_id}#follows/relay/#{SecureRandom.hex(16)}"

    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => activity_id,
      'type' => 'Follow',
      'actor' => @local_actor.ap_id,
      'object' => 'https://www.w3.org/ns/activitystreams#Public',
      'to' => ['https://www.w3.org/ns/activitystreams#Public']
    }
  end
end
