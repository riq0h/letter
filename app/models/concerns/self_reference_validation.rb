# frozen_string_literal: true

module SelfReferenceValidation
  extend ActiveSupport::Concern

  included do
    validate :cannot_target_self
  end

  private

  def cannot_target_self
    return unless actor_id == target_actor_id

    action = self.class.name.downcase
    errors.add(:target_actor, "cannot #{action} yourself")
  end
end
