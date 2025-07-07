# frozen_string_literal: true

FactoryBot.define do
  factory :unavailable_server do
    sequence(:domain) { |n| "unavailable#{n}.example.com" }
    reason { 'gone' }
    first_error_at { 1.hour.ago }
    last_error_at { 30.minutes.ago }
    error_count { 1 }
    last_error_message { 'HTTP 410 Gone' }
    auto_detected { true }
  end
end
