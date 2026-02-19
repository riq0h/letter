# frozen_string_literal: true

module ActivityBuilders
  class VoteActivityBuilder
    def initialize(activity)
      @activity = activity
    end

    def build
      vote_data = parse_vote_data

      {
        '@context' => Rails.application.config.activitypub.context_url,
        'id' => @activity.ap_id,
        'type' => 'Create',
        'actor' => @activity.actor.ap_id,
        'published' => @activity.published_at.iso8601,
        'object' => {
          'type' => 'Note',
          'id' => "#{@activity.ap_id}/vote",
          'attributedTo' => @activity.actor.ap_id,
          'name' => vote_data['vote_name'],
          'inReplyTo' => @activity.target_ap_id,
          'to' => target_actor_ap_id
        }
      }
    end

    private

    def parse_vote_data
      return {} unless @activity.raw_data

      if @activity.raw_data.is_a?(String)
        JSON.parse(@activity.raw_data)
      else
        @activity.raw_data
      end
    rescue JSON::ParserError
      {}
    end

    def target_actor_ap_id
      target_object = ActivityPubObject.find_by(ap_id: @activity.target_ap_id)
      target_object&.actor&.ap_id
    end
  end
end
