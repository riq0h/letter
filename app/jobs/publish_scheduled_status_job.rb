# frozen_string_literal: true

class PublishScheduledStatusJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(scheduled_status_id)
    scheduled_status = ScheduledStatus.find_by(id: scheduled_status_id)
    unless scheduled_status
      Rails.logger.warn "予約投稿が見つかりません (ID: #{scheduled_status_id})"
      return
    end

    scheduled_status.publish!
  end
end
