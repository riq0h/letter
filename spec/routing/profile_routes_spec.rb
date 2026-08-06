# frozen_string_literal: true

require 'rails_helper'

# Mastodon 4.6互換: GET/PATCH /api/v1/profile は既存実装のエイリアス
RSpec.describe 'profile routes', type: :routing do
  it 'routes GET /api/v1/profile to verify_credentials' do
    expect(get: '/api/v1/profile').to route_to('api/v1/accounts#verify_credentials')
  end

  it 'routes PATCH /api/v1/profile to update_credentials' do
    expect(patch: '/api/v1/profile').to route_to('api/v1/accounts#update_credentials')
  end
end
