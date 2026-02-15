# frozen_string_literal: true

module PollSerializer
  extend ActiveSupport::Concern

  private

  # 基本的なPollデータをシリアライズ
  def serialize_poll_base(poll)
    return nil if poll.blank?

    poll.to_mastodon_api
  end

  # 現在のアクターの投票情報を含むPollデータをシリアライズ
  def serialize_poll_with_actor(poll, actor = nil)
    return nil if poll.blank?

    result = poll.to_mastodon_api

    if actor
      result[:voted] = poll.voted_by?(actor)
      result[:own_votes] = poll.actor_choices(actor)
    end

    result
  end
end
