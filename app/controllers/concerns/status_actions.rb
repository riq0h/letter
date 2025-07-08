# frozen_string_literal: true

module StatusActions
  extend ActiveSupport::Concern

  private

  def create_like_activity(status)
    result = StatusActionOrganizer.call(current_user, action_type: 'like', status: status)

    unless result.success?
      Rails.logger.error "❌ Failed to create like activity: #{result.error}"
      raise StandardError, result.error
    end

    result.activity
  end

  def create_undo_like_activity(status, _favourite)
    result = StatusActionOrganizer.call(current_user, action_type: 'undo_like', status: status)

    unless result.success?
      Rails.logger.error "❌ Failed to create undo like activity: #{result.error}"
      return
    end

    result.activity
  end

  def create_announce_activity(status)
    result = StatusActionOrganizer.call(current_user, action_type: 'announce', status: status)

    unless result.success?
      Rails.logger.error "❌ Failed to create announce activity: #{result.error}"
      raise StandardError, result.error
    end

    result.activity
  end

  def create_undo_announce_activity(status, _reblog)
    result = StatusActionOrganizer.call(current_user, action_type: 'undo_announce', status: status)

    unless result.success?
      Rails.logger.error "❌ Failed to create undo announce activity: #{result.error}"
      return
    end

    result.activity
  end
end
