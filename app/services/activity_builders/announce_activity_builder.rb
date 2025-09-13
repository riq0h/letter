# frozen_string_literal: true

module ActivityBuilders
  class AnnounceActivityBuilder
    def initialize(activity)
      @activity = activity
    end

    def build
      target_object = ActivityPubObject.find_by(ap_id: @activity.target_ap_id)

      build_announce_data_structure(target_object)
    end

    private

    def build_announce_data_structure(target_object)
      cc_list, tag_list = build_announce_lists(target_object)

      {
        '@context' => Rails.application.config.activitypub.context_url,
        'id' => @activity.ap_id,
        'type' => 'Announce',
        'actor' => @activity.actor.ap_id,
        'object' => @activity.target_ap_id,
        'published' => @activity.published_at.iso8601,
        'to' => [Rails.application.config.activitypub.public_collection_url],
        'cc' => cc_list,
        'tag' => tag_list
      }
    end

    def build_announce_lists(target_object)
      cc_list = [@activity.actor.followers_url]
      tag_list = []

      if should_add_mention?(target_object)
        cc_list << target_object.actor.ap_id
        tag_list << build_mention_tag(target_object.actor)
      end

      [cc_list, tag_list]
    end

    def should_add_mention?(target_object)
      target_object&.actor
    end

    def build_mention_tag(actor)
      {
        'type' => 'Mention',
        'href' => actor.ap_id,
        'name' => "@#{actor.username}@#{actor.domain}"
      }
    end
  end
end
