# frozen_string_literal: true

FactoryBot.define do
  factory :activity_pub_object do
    actor
    object_type { 'Note' }
    content { Faker::Lorem.paragraph }
    visibility { 'public' }
    published_at { Time.current }
    local { true }
    language { 'ja' }
    sensitive { false }

    before(:create) do |object|
      if object.local? && object.ap_id.blank?
        base_url = Rails.application.config.activitypub.base_url
        object.ap_id = "#{base_url}/users/#{object.actor.username}/posts/#{SecureRandom.hex(8)}"
      end
    end

    trait :note do
      object_type { 'Note' }
    end

    trait :unlisted do
      visibility { 'unlisted' }
    end

    trait :private do
      visibility { 'private' }
    end

    trait :direct do
      visibility { 'direct' }
    end

    trait :sensitive do
      sensitive { true }
      summary { 'Sensitive content' }
    end

    trait :article do
      object_type { 'Article' }
      content { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    end

    trait :question do
      object_type { 'Question' }
      content { 'What do you think?' }
    end

    trait :remote do
      local { false }
      sequence(:ap_id) { |n| "https://remote.example.com/users/#{actor.username}/posts/#{n}" }
    end

    trait :with_media do
      after(:create) do |object|
        create(:media_attachment, object: object, actor: object.actor)
      end
    end

    trait :reply do
      sequence(:in_reply_to_ap_id) { |n| "https://example.com/posts/#{n}" }
    end
  end
end
