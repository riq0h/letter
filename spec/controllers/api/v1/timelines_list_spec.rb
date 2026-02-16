# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TimelinesController, type: :controller do
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

  describe 'GET #list' do
    let(:list) { create(:list, actor: user) }
    let(:member) { create(:actor, local: true) }

    before do
      create(:list_membership, list: list, actor: member)
    end

    it 'returns statuses from list members' do
      post_by_member = create(:activity_pub_object, :note, actor: member, visibility: 'public')
      post_by_stranger = create(:activity_pub_object, :note, actor: create(:actor, local: true), visibility: 'public')

      get :list, params: { id: list.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      ids = json.pluck('id')
      expect(ids).to include(post_by_member.id.to_s)
      expect(ids).not_to include(post_by_stranger.id.to_s)
    end

    it 'returns 404 for non-existent list' do
      get :list, params: { id: 99_999 }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for another users list' do
      other_user = create(:actor, local: true)
      other_list = create(:list, actor: other_user)

      get :list, params: { id: other_list.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns empty array for list with no members' do
      empty_list = create(:list, actor: user)

      get :list, params: { id: empty_list.id }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      get :list, params: { id: list.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
