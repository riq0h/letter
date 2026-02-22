# frozen_string_literal: true

FactoryBot.define do
  factory :relay do
    sequence(:inbox_url) { |n| "https://relay#{n}.example.com/inbox" }
    state { 'idle' }

    trait :pending do
      state { 'pending' }
      follow_activity_id { "https://example.com/activities/#{SecureRandom.hex(8)}" }
    end

    trait :accepted do
      state { 'accepted' }
      follow_activity_id { "https://example.com/activities/#{SecureRandom.hex(8)}" }
    end

    trait :rejected do
      state { 'rejected' }
    end
  end
end
