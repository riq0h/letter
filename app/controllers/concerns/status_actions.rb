# frozen_string_literal: true

module StatusActions
  extend ActiveSupport::Concern

  private

  def create_like_activity(status)
    execute_status_action('like', status)
  end

  def create_undo_like_activity(status, _favourite = nil)
    execute_status_action('undo_like', status)
  end

  def create_announce_activity(status)
    execute_status_action('announce', status)
  end

  def create_undo_announce_activity(status, _reblog = nil)
    execute_status_action('undo_announce', status)
  end

  def execute_status_action(action_type, status)
    result = StatusActionOrganizer.call(current_user, action_type: action_type, status: status)

    unless result.success?
      Rails.logger.error "❌ Failed to create #{action_type} activity: #{result.error}"
      raise StandardError, result.error
    end

    result.activity
  end
end
