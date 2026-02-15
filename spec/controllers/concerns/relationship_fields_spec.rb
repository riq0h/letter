# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AccountsController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:other_user) { create(:actor, local: true) }
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

  describe 'GET #relationships' do
    it 'includes languages field' do
      get :relationships, params: { id: [other_user.id] }

      json = response.parsed_body
      expect(json.first).to have_key('languages')
      expect(json.first['languages']).to be_nil
    end

    it 'includes requested_by field' do
      get :relationships, params: { id: [other_user.id] }

      json = response.parsed_body
      expect(json.first).to have_key('requested_by')
      expect(json.first['requested_by']).to be(false)
    end

    it 'sets requested_by to true when other user has pending follow request' do
      user.update!(manually_approves_followers: true)
      create(:follow, actor: other_user, target_actor: user, accepted: false)

      get :relationships, params: { id: [other_user.id] }

      json = response.parsed_body
      expect(json.first['requested_by']).to be(true)
    end

    it 'includes note field' do
      get :relationships, params: { id: [other_user.id] }

      json = response.parsed_body
      expect(json.first).to have_key('note')
    end

    it 'returns default values for non-existent accounts' do
      get :relationships, params: { id: [99_999] }

      json = response.parsed_body
      expect(json.first['languages']).to be_nil
      expect(json.first['requested_by']).to be(false)
      expect(json.first['note']).to eq('')
    end
  end

  describe 'GET #lists' do
    it 'returns lists containing the account' do
      list = create(:list, actor: user, title: 'Friends')
      create(:list_membership, list: list, actor: other_user)

      get :lists, params: { id: other_user.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['title']).to eq('Friends')
    end

    it 'returns empty array when account is not in any list' do
      get :lists, params: { id: other_user.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end
  end
end
