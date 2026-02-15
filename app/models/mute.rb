# frozen_string_literal: true

class Mute < ApplicationRecord
  include ApIdGeneration
  include SelfReferenceValidation

  belongs_to :actor, class_name: 'Actor'
  belongs_to :target_actor, class_name: 'Actor'

  validates :actor_id, uniqueness: { scope: :target_actor_id }
  validates :ap_id, presence: true, uniqueness: true
end
