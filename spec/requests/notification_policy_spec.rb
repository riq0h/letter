# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notification policy', type: :request do
  let(:user) { create(:actor) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Client', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application, scopes: 'read write')
  end
  let(:auth) { { 'Authorization' => "Bearer #{access_token.token}" } }
  let(:summary) { { 'pending_requests_count' => 0, 'pending_notifications_count' => 0 } }

  it 'reports through v1 that no notifications are filtered' do
    get '/api/v1/notifications/policy', headers: auth

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'filter_not_following' => false, 'filter_not_followers' => false,
      'filter_new_accounts' => false, 'filter_private_mentions' => false, 'summary' => summary
    )
  end

  it 'reports through v2 that every notification is accepted' do
    get '/api/v2/notifications/policy', headers: auth

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'for_not_following' => 'accept', 'for_not_followers' => 'accept', 'for_new_accounts' => 'accept',
      'for_private_mentions' => 'accept', 'for_limited_accounts' => 'accept', 'summary' => summary
    )
  end

  it 'requires a token' do
    get '/api/v1/notifications/policy'

    expect(response).to have_http_status(:unauthorized)
  end
end
