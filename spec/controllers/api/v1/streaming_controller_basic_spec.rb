# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::StreamingController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:application) do
    Doorkeeper::Application.create!(
      name: 'Test App',
      redirect_uri: 'https://localhost',
      confidential: false
    )
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application: application,
      scopes: 'read:statuses read:notifications',
      expires_in: 2.hours
    )
  end

  describe 'Basic functionality' do
    context 'without authentication' do
      it 'returns unauthorized' do
        get :index, params: { stream: 'public' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with authentication' do
      before do
        request.headers['Authorization'] = "Bearer #{access_token.token}"
      end

      it 'returns OK for public stream' do
        get :index, params: { stream: 'public', since_id: 0 }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/json')
      end

      it 'returns empty array for unknown stream' do
        get :index, params: { stream: 'unknown', since_id: 0 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end

      it 'sets CORS headers' do
        get :index, params: { stream: 'public', since_id: 0 }

        expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')
      end
    end
  end
end
