# frozen_string_literal: true

FactoryBot.define do
  factory :quote_authorization do
    actor { association :actor }
    quote_post { association :quote_post }
    ap_id { "https://example.com/quote_auth/#{SecureRandom.hex(8)}" }
    interacting_object_id { "https://example.com/posts/#{SecureRandom.hex(8)}" }
    interaction_target_id { "https://example.com/posts/#{SecureRandom.hex(8)}" }
  end
end
