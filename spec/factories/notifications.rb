# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    association :account, factory: :actor
    association :from_account, factory: :actor
    notification_type { 'mention' }
    activity_type { 'ActivityPubObject' }
    activity_id { create(:activity_pub_object).id.to_s }
    read { false }

    trait :read do
      read { true }
    end

    trait :follow_notification do
      notification_type { 'follow' }
      activity_type { 'Follow' }
      activity_id { create(:follow).id.to_s }
    end

    trait :favourite_notification do
      notification_type { 'favourite' }
      activity_type { 'ActivityPubObject' }
    end

    trait :reblog_notification do
      notification_type { 'reblog' }
      activity_type { 'ActivityPubObject' }
    end

    trait :mention_notification do
      notification_type { 'mention' }
      activity_type { 'ActivityPubObject' }
    end

    trait :follow_request_notification do
      notification_type { 'follow_request' }
      activity_type { 'Follow' }
      activity_id { create(:follow).id.to_s }
    end

    trait :poll_notification do
      notification_type { 'poll' }
      activity_type { 'ActivityPubObject' }
    end
  end
end
