# frozen_string_literal: true

class RelayFollowService
  include ActivityPubHelper
  include RelayActorManagement

  def call(relay)
    @relay = relay
    @local_actor = local_actor

    return false unless @local_actor && @relay&.idle?

    begin
      relay_actor_data = fetch_relay_actor_data
      return false unless relay_actor_data

      follow_activity = create_follow_activity(relay_actor_data)
      handle_follow_result(follow_activity)
    rescue StandardError => e
      handle_error(e)
    end
  end

  private

  def fetch_relay_actor_data
    relay_actor_data = fetch_activitypub_object(@relay.actor_uri)

    unless relay_actor_data
      error_msg = "リレーアクター情報の取得に失敗しました: #{@relay.actor_uri}"
      Rails.logger.error error_msg
      @relay.update!(last_error: error_msg)
    end

    relay_actor_data
  end

  def handle_follow_result(follow_activity)
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
  end

  def handle_error(error)
    Rails.logger.error "Relay follow error: #{error.message}"
    @relay.update!(last_error: error.message)
    false
  end

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
