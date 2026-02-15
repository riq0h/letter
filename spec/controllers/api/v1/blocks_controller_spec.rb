# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BlocksController, type: :controller do
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
      scopes: 'read write',
      expires_in: 2.hours
    )
  end

  before do
    request.headers['Authorization'] = "Bearer #{access_token.token}"
  end

  describe 'GET #index' do
    it 'returns blocked accounts' do
      blocked_user = create(:actor, local: true)
      create(:block, actor: user, target_actor: blocked_user)

      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(blocked_user.id.to_s)
    end

    it 'returns empty array when no blocks' do
      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end

    it 'paginates with max_id' do
      blocked1 = create(:actor, local: true)
      blocked2 = create(:actor, local: true)
      create(:block, actor: user, target_actor: blocked1)
      block2 = create(:block, actor: user, target_actor: blocked2)

      get :index, params: { max_id: block2.id }

      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(blocked1.id.to_s)
    end

    it 'sets Link pagination headers when results fill limit' do
      21.times do
        blocked = create(:actor, local: true)
        create(:block, actor: user, target_actor: blocked)
      end

      get :index, params: { limit: 20 }

      expect(response.headers['Link']).to be_present
      expect(response.headers['Link']).to include('rel="next"')
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
