# frozen_string_literal: true

FactoryBot.define do
  factory :reblog do
    actor
    object { create(:activity_pub_object) }

    trait :with_existing_object do
      transient do
        existing_object { create(:activity_pub_object) }
      end

      object { existing_object }
    end
  end
end
