# frozen_string_literal: true

FactoryBot.define do
  factory :tag do
    sequence(:name) { |n| "tag#{n}" }
    usage_count { 1 }

    trait :popular do
      usage_count { 100 }
    end

    trait :trending do
      usage_count { 50 }
    end
  end
end
