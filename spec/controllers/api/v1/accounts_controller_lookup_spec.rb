# frozen_string_literal: true

require 'rails_helper'

# GET /api/v1/accounts/lookup はMastodonと同じくログインなしでも使える
RSpec.describe Api::V1::AccountsController, type: :controller do
  let(:local_user) { create(:actor, username: 'alice') }
  let(:local_domain) { Rails.application.config.activitypub.domain }

  context 'without a token' do
    it 'finds a local account by user name' do
      local_user

      get :lookup, params: { acct: 'alice' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(local_user.id.to_s)
    end

    it 'treats user@this-server as the local account' do
      local_user

      get :lookup, params: { acct: "alice@#{local_domain}" }

      expect(response.parsed_body['id']).to eq(local_user.id.to_s)
    end

    it 'finds an already known remote account' do
      remote = create(:actor, :remote, username: 'bob', domain: 'remote.example')

      get :lookup, params: { acct: 'bob@remote.example' }

      expect(response.parsed_body['id']).to eq(remote.id.to_s)
    end

    it 'does not query other servers for an unknown account' do
      expect(Search::RemoteResolverService).not_to receive(:new)

      get :lookup, params: { acct: 'nobody@unknown.example' }

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'with a token' do
    let(:application) { Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false) }
    let(:access_token) do
      Doorkeeper::AccessToken.create!(resource_owner_id: local_user.id, application: application, scopes: 'read', expires_in: 2.hours)
    end

    before { request.headers['Authorization'] = "Bearer #{access_token.token}" }

    it 'resolves an unknown remote account via WebFinger' do
      remote = create(:actor, :remote, username: 'carol', domain: 'remote.example')
      resolver = instance_double(Search::RemoteResolverService, resolve_remote_account: remote)
      allow(Search::RemoteResolverService).to receive(:new).and_return(resolver)

      get :lookup, params: { acct: 'carol@other.example' }

      expect(response.parsed_body['id']).to eq(remote.id.to_s)
      expect(resolver).to have_received(:resolve_remote_account).with('carol@other.example')
    end

    it 'rejects an invalid token' do
      request.headers['Authorization'] = 'Bearer invalid'

      get :lookup, params: { acct: 'alice' }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
