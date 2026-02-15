# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::MutesController, type: :controller do
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
    it 'returns muted accounts' do
      muted_user = create(:actor, local: true)
      create(:mute, actor: user, target_actor: muted_user)

      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(muted_user.id.to_s)
    end

    it 'returns empty array when no mutes' do
      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end

    it 'paginates with max_id' do
      muted1 = create(:actor, local: true)
      muted2 = create(:actor, local: true)
      create(:mute, actor: user, target_actor: muted1)
      mute2 = create(:mute, actor: user, target_actor: muted2)

      get :index, params: { max_id: mute2.id }

      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(muted1.id.to_s)
    end

    it 'sets Link pagination headers' do
      21.times { create(:mute, actor: user, target_actor: create(:actor, local: true)) }

      get :index, params: { limit: 20 }

      expect(response.headers['Link']).to be_present
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
