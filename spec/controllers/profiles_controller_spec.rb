# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProfilesController, type: :controller do
  let(:actor) { create(:actor, username: 'testuser', local: true) }

  describe 'GET #redirect_to_frontend' do
    context 'when request is from browser' do
      before do
        request.headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        request.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      end

      it 'redirects to frontend profile URL' do
        get :redirect_to_frontend, params: { username: actor.username }

        expected_path = profile_path(username: actor.username)
        expect(response).to redirect_to(expected_path)
        expect(response.status).to eq(301)
      end
    end

    context 'when request is from ActivityPub client' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns ActivityPub JSON response' do
        get :redirect_to_frontend, params: { username: actor.username }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')

        json_response = response.parsed_body
        expect(json_response['type']).to eq('Person')
        expect(json_response['preferredUsername']).to eq(actor.username)
        expect(json_response['id']).to eq(actor.ap_id)
      end
    end

    context 'when ActivityPub client uses application/ld+json' do
      before do
        request.headers['Accept'] = 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
      end

      it 'returns ActivityPub JSON response' do
        get :redirect_to_frontend, params: { username: actor.username }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')
      end
    end

    context 'when ActivityPub client uses Mastodon User-Agent' do
      before do
        request.headers['Accept'] = '*/*'
        request.headers['User-Agent'] = 'Mastodon/4.0.0'
      end

      it 'returns ActivityPub JSON response based on User-Agent' do
        get :redirect_to_frontend, params: { username: actor.username }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')
      end
    end

    context 'when actor does not exist' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns 404 error for ActivityPub request' do
        get :redirect_to_frontend, params: { username: 'nonexistent' }

        expect(response.status).to eq(404)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('Actor not found')
      end
    end
  end

  describe 'GET #show' do
    it 'renders HTML page for frontend display' do
      get :show, params: { username: actor.username }

      expect(response.status).to eq(200)
      expect(response.content_type).to include('text/html')
    end

    context 'when request is from ActivityPub client' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns ActivityPub JSON response' do
        get :show, params: { username: actor.username }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')
      end
    end
  end
end
