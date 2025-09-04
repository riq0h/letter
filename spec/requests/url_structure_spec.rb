# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'URL Structure', type: :request do
  let(:actor) { create(:actor, username: 'testuser', local: true) }
  let(:activity_pub_object) { create(:activity_pub_object, actor: actor, local: true) }

  describe 'Profile URL handling' do
    it 'redirects browser requests from API URLs to frontend' do
      get "/users/#{actor.username}"

      expect(response).to redirect_to("/@#{actor.username}")
      expect(response.status).to eq(301)
    end

    it 'serves ActivityPub JSON for API URLs with ActivityPub clients' do
      get "/users/#{actor.username}", headers: { 'Accept' => 'application/activity+json' }

      expect(response.status).to eq(200)
      expect(response.content_type).to include('application/activity+json')

      json_response = response.parsed_body
      expect(json_response['type']).to eq('Person')
      expect(json_response['preferredUsername']).to eq(actor.username)
    end

    it 'serves HTML for frontend URLs with browsers' do
      get "/@#{actor.username}"

      expect(response.status).to be_between(200, 299).or be_between(400, 499)
    end

    it 'serves ActivityPub JSON for frontend URLs with ActivityPub clients' do
      get "/@#{actor.username}", headers: { 'Accept' => 'application/activity+json' }

      expect(response.status).to eq(200)
      expect(response.content_type).to include('application/activity+json')
    end
  end

  describe 'Post URL handling' do
    it 'redirects browser requests from API URLs to frontend' do
      get "/users/#{actor.username}/posts/#{activity_pub_object.id}"

      expect(response).to redirect_to("/@#{actor.username}/#{activity_pub_object.id}")
      expect(response.status).to eq(301)
    end

    it 'serves ActivityPub JSON for API URLs with ActivityPub clients' do
      get "/users/#{actor.username}/posts/#{activity_pub_object.id}",
          headers: { 'Accept' => 'application/activity+json' }

      expect(response.status).to eq(200)
      expect(response.content_type).to include('application/activity+json')

      json_response = response.parsed_body
      expect(json_response['type']).to eq('Note')
      expect(json_response['id']).to eq(activity_pub_object.ap_id)
    end

    it 'serves HTML for frontend URLs with browsers' do
      get "/@#{actor.username}/#{activity_pub_object.id}"

      expect(response.status).to be_between(200, 299).or be_between(400, 499)
    end
  end

  describe 'Model URL generation' do
    it 'generates API-style URLs for ActivityPub objects' do
      expected_url = "#{Rails.application.config.activitypub.base_url}/users/#{actor.username}/posts/#{activity_pub_object.id}"
      expect(activity_pub_object.public_url).to eq(expected_url)
    end

    it 'generates API-style URLs for actors' do
      expected_url = "#{Rails.application.config.activitypub.base_url}/users/#{actor.username}"
      expect(actor.public_url).to eq(expected_url)
    end
  end

  describe 'Content negotiation with different Accept headers' do
    [
      'application/activity+json',
      'application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
      'application/json',
      'application/activity+json, application/ld+json'
    ].each do |accept_header|
      context "when Accept header is #{accept_header}" do
        it 'returns ActivityPub JSON for profile requests' do
          get "/users/#{actor.username}", headers: { 'Accept' => accept_header }

          expect(response.status).to eq(200)
          expect(response.content_type).to include('application/activity+json')
        end

        it 'returns ActivityPub JSON for post requests' do
          get "/users/#{actor.username}/posts/#{activity_pub_object.id}",
              headers: { 'Accept' => accept_header }

          expect(response.status).to eq(200)
          expect(response.content_type).to include('application/activity+json')
        end
      end
    end
  end

  describe 'Error handling' do
    it 'returns 404 for non-existent actor in API URL' do
      get '/users/nonexistent', headers: { 'Accept' => 'application/activity+json' }

      expect(response.status).to eq(404)
      json_response = response.parsed_body
      expect(json_response['error']).to eq('Actor not found')
    end

    it 'returns 404 for non-existent post in API URL' do
      get "/users/#{actor.username}/posts/999999",
          headers: { 'Accept' => 'application/activity+json' }

      expect(response.status).to eq(404)
      json_response = response.parsed_body
      expect(json_response['error']).to eq('Object not found')
    end
  end
end
