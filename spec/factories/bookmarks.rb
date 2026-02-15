# frozen_string_literal: true

FactoryBot.define do
  factory :bookmark do
    actor
    object { create(:activity_pub_object) }
  end
end
