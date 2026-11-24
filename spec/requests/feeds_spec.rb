# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Feeds', type: :request do
  let(:actor) { create(:actor, username: 'alice') }

  before do
    create(:activity_pub_object, actor: actor, object_type: 'Note', visibility: 'public',
                                 content: 'feed entry', published_at: 1.hour.ago)
  end

  describe 'GET /local.atom' do
    it 'returns the Atom feed to a feed reader' do
      get '/local.atom', headers: { 'Accept' => 'application/atom+xml' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/atom+xml')
    end

    it 'returns the Atom feed to a browser asking for HTML' do
      get '/local.atom', headers: { 'Accept' => 'text/html,application/xhtml+xml' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/atom+xml')
      expect(response.body).to include('feed entry')
    end
  end

  describe 'GET /@:username.rss' do
    it 'returns the RSS feed to a browser asking for HTML' do
      get '/@alice.rss', headers: { 'Accept' => 'text/html,application/xhtml+xml' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/rss+xml')
      expect(response.body).to include('feed entry')
    end
  end
end
