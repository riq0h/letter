# frozen_string_literal: true

require 'rails_helper'

# Mastodon 4.5公式の引用API互換:
# - POST /api/v1/statuses の quoted_status_id を既存QuotePost機構へマッピング
# - Statusエンティティの quote は公式形({state:, quoted_status:})、quotes_count付き
# - GET /api/v1/statuses/:id/quotes で引用した投稿一覧
RSpec.describe Api::V1::StatusesController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:other) { create(:actor, local: true) }
  let(:quoted) { create(:activity_pub_object, :note, actor: other, visibility: 'public', content: '引用される投稿') }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write', expires_in: 2.hours)
  end

  before { request.headers['Authorization'] = "Bearer #{access_token.token}" }

  describe 'POST #create with quoted_status_id (official quote authoring)' do
    it 'creates a status linked to the quoted status via QuotePost' do
      expect do
        post :create, params: { status: '公式パラメータでの引用', quoted_status_id: quoted.id }
      end.to change(QuotePost, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['quote']['state']).to eq('accepted')
      expect(body['quote']['quoted_status']['id']).to eq(quoted.id.to_s)

      quote_post = QuotePost.last
      expect(quote_post.quoted_object).to eq(quoted)
      expect(quote_post.object.id).to eq(body['id'])
    end

    it 'returns 404 for an unknown quoted_status_id' do
      post :create, params: { status: 'x', quoted_status_id: 'nonexistent' }

      expect(response).to have_http_status(:not_found)
      expect(QuotePost.count).to eq(0)
    end

    it 'does not affect plain status creation' do
      post :create, params: { status: '普通の投稿' }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['quote']).to be_nil
      expect(response.parsed_body['quotes_count']).to eq(0)
    end
  end

  describe 'GET #quotes' do
    it 'lists statuses quoting the target and counts them in quotes_count' do
      post :create, params: { status: '引用です', quoted_status_id: quoted.id }
      quoting_id = response.parsed_body['id']

      get :quotes, params: { id: quoted.id }
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.pluck('id')
      expect(ids).to include(quoting_id)

      get :show, params: { id: quoted.id }
      expect(response.parsed_body['quotes_count']).to eq(1)
    end
  end
end
