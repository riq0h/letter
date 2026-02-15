# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::StatusesController, type: :controller do
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

  describe 'POST #mute' do
    it 'returns status with muted true' do
      status = create(:activity_pub_object, :note, actor: user)

      post :mute, params: { id: status.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['id']).to eq(status.id.to_s)
      expect(json['muted']).to be(true)
    end

    it 'requires authentication' do
      status = create(:activity_pub_object, :note, actor: user)
      request.headers['Authorization'] = nil

      post :mute, params: { id: status.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST #unmute' do
    it 'returns status with muted false' do
      status = create(:activity_pub_object, :note, actor: user)

      post :unmute, params: { id: status.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['id']).to eq(status.id.to_s)
      expect(json['muted']).to be(false)
    end

    it 'requires authentication' do
      status = create(:activity_pub_object, :note, actor: user)
      request.headers['Authorization'] = nil

      post :unmute, params: { id: status.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
