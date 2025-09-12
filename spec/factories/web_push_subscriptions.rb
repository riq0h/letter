# frozen_string_literal: true

FactoryBot.define do
  factory :web_push_subscription do
    association :actor, factory: :actor

    endpoint { 'https://fcm.googleapis.com/fcm/send/example' }
    p256dh_key { 'BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4wZjZftyNVPpFe1KGWd2NvsXpjBSGkNNDvs_' }
    auth_key { 'tBHSfkKbjMsJ1SFOkosUPw==' }

    trait :active do
      # デフォルトでアクティブ
    end

    trait :with_alerts do
      after(:create) do |subscription|
        subscription.alerts = {
          'mention' => true,
          'follow' => true,
          'favourite' => true,
          'reblog' => true,
          'poll' => true,
          'status' => true,
          'update' => true,
          'follow_request' => true,
          'quote' => true,
          'admin.sign_up' => false,
          'admin.report' => false
        }
        subscription.save!
      end
    end
  end
end
