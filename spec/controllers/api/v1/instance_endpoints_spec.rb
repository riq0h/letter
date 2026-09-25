# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InstanceController, type: :controller do
  describe 'GET #peers' do
    it 'returns list of known domains' do
      create(:actor, :remote, domain: 'mastodon.social')
      create(:actor, :remote, domain: 'pleroma.example.com')

      get :peers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to include('mastodon.social')
      expect(json).to include('pleroma.example.com')
    end

    it 'returns unique domains' do
      create(:actor, :remote, domain: 'mastodon.social')
      create(:actor, :remote, domain: 'mastodon.social')

      get :peers

      json = response.parsed_body
      expect(json.count('mastodon.social')).to eq(1)
    end

    it 'does not include local domain' do
      create(:actor, local: true)

      get :peers

      json = response.parsed_body
      expect(json).not_to include(nil)
    end
  end

  describe 'GET #activity' do
    it 'returns weekly activity stats' do
      get :activity

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to be_an(Array)
      expect(json.length).to eq(12)
      expect(json.first).to have_key('week')
      expect(json.first).to have_key('statuses')
      expect(json.first).to have_key('logins')
      expect(json.first).to have_key('registrations')
    end
  end

  describe 'GET #rules' do
    it 'returns empty array' do
      get :rules

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to eq([])
    end
  end

  describe 'GET #extended_description' do
    it 'returns the instance description in Mastodon ExtendedDescription form' do
      InstanceConfig.set('instance_description', 'テスト用の説明文')

      get :extended_description

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['content']).to eq('テスト用の説明文')
      expect { Time.iso8601(json['updated_at']) }.not_to raise_error
    end

    it 'returns empty content when no description is configured' do
      get :extended_description

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('content' => be_a(String), 'updated_at' => be_present)
    end
  end
end
