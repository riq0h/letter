# frozen_string_literal: true

class UpdateReplyCountJob < ApplicationJob
  queue_as :default

  def perform(in_reply_to_ap_id)
    return if in_reply_to_ap_id.blank?

    parent = ActivityPubObject.find_by(ap_id: in_reply_to_ap_id)
    return unless parent

    ActivityPubObject.update_counters(parent.id, replies_count: 1)
  end
end
