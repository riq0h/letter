# frozen_string_literal: true

class AccountNote < ApplicationRecord
  include SelfReferenceValidation

  belongs_to :actor, class_name: 'Actor'
  belongs_to :target_actor, class_name: 'Actor'

  validates :comment, presence: true, length: { maximum: 2000 }
  validates :actor_id, uniqueness: { scope: :target_actor_id }
end
