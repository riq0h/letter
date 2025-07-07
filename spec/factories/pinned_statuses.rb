# frozen_string_literal: true

FactoryBot.define do
  factory :pinned_status do
    actor
    association :object, factory: %i[activity_pub_object note]
    position { 0 }
  end
end
