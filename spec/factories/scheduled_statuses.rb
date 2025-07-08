# frozen_string_literal: true

FactoryBot.define do
  factory :scheduled_status do
    association :actor, factory: :actor

    params do
      {
        'status' => 'Scheduled status content',
        'visibility' => 'public',
        'sensitive' => false
      }
    end

    scheduled_at { 1.hour.from_now }
    media_attachment_ids { [] }

    trait :with_media do
      transient do
        media_count { 1 }
      end

      after(:build) do |scheduled_status, evaluator|
        media_attachments = create_list(:media_attachment, evaluator.media_count,
                                        actor: scheduled_status.actor)
        scheduled_status.media_attachment_ids = media_attachments.map(&:id)
      end
    end

    trait :with_poll do
      params do
        {
          'status' => 'Poll question?',
          'visibility' => 'public',
          'poll' => {
            'options' => ['Option 1', 'Option 2'],
            'expires_in' => 3600,
            'multiple' => false,
            'hide_totals' => false
          }
        }
      end
    end

    trait :sensitive do
      params do
        {
          'status' => 'Sensitive content',
          'visibility' => 'public',
          'sensitive' => true,
          'spoiler_text' => 'Content Warning'
        }
      end
    end

    trait :due do
      scheduled_at { 1.hour.ago }
    end

    trait :pending do
      scheduled_at { 1.hour.from_now }
    end

    trait :reply do
      transient do
        in_reply_to { nil }
      end

      params do
        base_params = {
          'status' => 'This is a reply',
          'visibility' => 'public'
        }

        if in_reply_to
          base_params['in_reply_to_id'] = in_reply_to.respond_to?(:ap_id) ? in_reply_to.ap_id : in_reply_to
        end

        base_params
      end
    end
  end
end
