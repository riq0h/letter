# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::BookmarksController, type: :controller do
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
    it 'returns bookmarked statuses' do
      status = create(:activity_pub_object, :note, actor: user)
      create(:bookmark, actor: user, object: status)

      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(status.id.to_s)
    end

    it 'returns empty array when no bookmarks' do
      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end

    it 'paginates with max_id' do
      status1 = create(:activity_pub_object, :note, actor: user)
      status2 = create(:activity_pub_object, :note, actor: user)
      create(:bookmark, actor: user, object: status1)
      bookmark2 = create(:bookmark, actor: user, object: status2)

      get :index, params: { max_id: bookmark2.id }

      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(status1.id.to_s)
    end

    it 'sets Link pagination headers when results fill limit' do
      21.times do
        status = create(:activity_pub_object, :note, actor: user)
        create(:bookmark, actor: user, object: status)
      end

      get :index, params: { limit: 20 }

      expect(response.headers['Link']).to be_present
      expect(response.headers['Link']).to include('rel="next"')
    end

    it 'respects limit parameter' do
      5.times do
        status = create(:activity_pub_object, :note, actor: user)
        create(:bookmark, actor: user, object: status)
      end

      get :index, params: { limit: 2 }

      json = response.parsed_body
      expect(json.length).to eq(2)
    end

    it 'paginates with since_id' do
      status1 = create(:activity_pub_object, :note, actor: user)
      status2 = create(:activity_pub_object, :note, actor: user)
      bookmark1 = create(:bookmark, actor: user, object: status1)
      create(:bookmark, actor: user, object: status2)

      get :index, params: { since_id: bookmark1.id }

      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['id']).to eq(status2.id.to_s)
    end

    it 'includes prev Link header when paginating with max_id' do
      3.times do
        status = create(:activity_pub_object, :note, actor: user)
        create(:bookmark, actor: user, object: status)
      end
      max_id = user.bookmarks.order(id: :desc).first.id

      get :index, params: { max_id: max_id }

      expect(response.headers['Link']).to be_present
      expect(response.headers['Link']).to include('rel="prev"')
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
