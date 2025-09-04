# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PostsController, type: :controller do
  let(:actor) { create(:actor, username: 'testuser', local: true) }
  let(:activity_pub_object) { create(:activity_pub_object, actor: actor, local: true) }

  describe 'GET #redirect_to_frontend' do
    context 'when request is from browser' do
      it 'redirects to frontend URL' do
        get :redirect_to_frontend, params: { username: actor.username, id: activity_pub_object.id }

        expected_path = post_html_path(username: actor.username, id: activity_pub_object.id)
        expect(response).to redirect_to(expected_path)
        expect(response.status).to eq(301)
      end
    end

    context 'when request is from ActivityPub client' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns ActivityPub JSON response' do
        get :redirect_to_frontend, params: { username: actor.username, id: activity_pub_object.id }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')

        json_response = response.parsed_body
        expect(json_response['type']).to eq('Note')
        expect(json_response['id']).to eq(activity_pub_object.ap_id)
      end
    end

    context 'when ActivityPub client uses application/ld+json' do
      before do
        request.headers['Accept'] = 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
      end

      it 'returns ActivityPub JSON response' do
        get :redirect_to_frontend, params: { username: actor.username, id: activity_pub_object.id }

        expect(response.status).to eq(200)
        expect(response.content_type).to include('application/activity+json')
      end
    end

    context 'when actor does not exist' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns 404 error for ActivityPub request' do
        get :redirect_to_frontend, params: { username: 'nonexistent', id: activity_pub_object.id }

        expect(response.status).to eq(404)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('Actor not found')
      end
    end

    context 'when object does not exist' do
      before do
        request.headers['Accept'] = 'application/activity+json'
      end

      it 'returns 404 error for ActivityPub request' do
        get :redirect_to_frontend, params: { username: actor.username, id: '999999' }

        expect(response.status).to eq(404)
        json_response = response.parsed_body
        expect(json_response['error']).to eq('Object not found')
      end
    end
  end

  describe 'GET #show_html' do
    it 'renders HTML page for frontend display' do
      get :show_html, params: { username: actor.username, id: activity_pub_object.id }

      expect(response.status).to eq(200)
      expect(response.content_type).to include('text/html')
    end

    it 'returns 404 when post not found' do
      get :show_html, params: { username: actor.username, id: '999999' }

      expect(response.status).to eq(404)
    end
  end
end
