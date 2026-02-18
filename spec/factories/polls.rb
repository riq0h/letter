# frozen_string_literal: true

FactoryBot.define do
  factory :poll do
    object { association :activity_pub_object, object_type: 'Question' }
    options { [{ 'title' => 'Option 1' }, { 'title' => 'Option 2' }] }
    expires_at { 1.day.from_now }
    multiple { false }
    votes_count { 0 }
    voters_count { 0 }

    trait :multiple_choice do
      multiple { true }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :with_votes do
      votes_count { 5 }
      voters_count { 5 }
    end

    trait :remote do
      transient do
        remote_actor { association :actor, :remote }
      end
      object { association :activity_pub_object, :remote, object_type: 'Question', actor: remote_actor }
      options do
        [
          { 'title' => 'Option 1', 'votes_count' => 10 },
          { 'title' => 'Option 2', 'votes_count' => 5 }
        ]
      end
      votes_count { 15 }
      voters_count { 15 }
    end

    trait :remote_expired do
      remote
      expires_at { 1.day.ago }
    end
  end
end
