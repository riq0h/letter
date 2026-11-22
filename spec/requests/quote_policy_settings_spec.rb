# frozen_string_literal: true

require 'rails_helper'

# クライアントが引用の作成を有効にするための情報(Mastodon 4.5互換)
RSpec.describe 'Quote settings for clients', type: :request do
  let(:user) { create(:actor) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write', expires_in: 2.hours)
  end
  let(:auth) { { 'Authorization' => "Bearer #{access_token.token}" } }

  it 'reports the API version clients check before offering quotes' do
    Rails.cache.delete('api:v2:instance')

    get '/api/v2/instance'

    expect(response.parsed_body['api_versions']).to eq('mastodon' => 7)
  end

  it 'reports the default quote policy in the preferences and the account' do
    get '/api/v1/preferences', headers: auth
    expect(response.parsed_body['posting:default:quote_policy']).to eq('public')

    get '/api/v1/accounts/verify_credentials', headers: auth
    expect(response.parsed_body['source']['quote_policy']).to eq('public')
  end

  it 'changes the default quote policy from the account settings' do
    patch '/api/v1/accounts/update_credentials', params: { source: { quote_policy: 'followers' } }, headers: auth

    expect(response).to have_http_status(:ok)
    expect(user.reload.setting('posting:default:quote_policy')).to eq('followers')
    expect(response.parsed_body['source']['quote_policy']).to eq('followers')
  end

  it 'ignores an unknown default quote policy' do
    patch '/api/v1/accounts/update_credentials', params: { source: { quote_policy: 'everyone' } }, headers: auth

    expect(user.reload.setting('posting:default:quote_policy')).to eq('public')
  end
end
