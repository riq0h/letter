# frozen_string_literal: true

FactoryBot.define do
  factory :object_tag do
    association :object, factory: :activity_pub_object
    association :tag
  end
end
