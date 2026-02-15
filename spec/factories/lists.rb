# frozen_string_literal: true

FactoryBot.define do
  factory :list do
    actor
    title { "List #{SecureRandom.hex(4)}" }
    replies_policy { 'list' }
    exclusive { false }
  end
end
