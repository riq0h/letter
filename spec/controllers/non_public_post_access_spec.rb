# frozen_string_literal: true

require 'rails_helper'

# フォロワー限定(private)・DM(direct)の投稿を、認証なしで閲覧・取得させない
RSpec.describe 'Non-public post access' do # rubocop:disable RSpec/DescribeClass
  let(:owner) { create(:actor, username: 'owner', local: true) }
  let(:public_post) { create(:activity_pub_object, actor: owner, local: true, visibility: 'public') }
  let(:unlisted_post) { create(:activity_pub_object, actor: owner, local: true, visibility: 'unlisted') }
  let(:private_post) { create(:activity_pub_object, actor: owner, local: true, visibility: 'private') }
  let(:direct_post) { create(:activity_pub_object, actor: owner, local: true, visibility: 'direct') }

  describe PostsController, type: :controller do
    it 'shows public and unlisted posts to anyone' do
      [public_post, unlisted_post].each do |post|
        get :show_html, params: { username: owner.username, id: post.id }
        expect(response).to have_http_status(:ok)
      end
    end

    it 'hides followers-only posts and DMs from anonymous viewers' do
      [private_post, direct_post].each do |post|
        get :show_html, params: { username: owner.username, id: post.id }
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'shows a DM page to its author without public caching' do
      session[:current_user_id] = owner.id

      get :show_html, params: { username: owner.username, id: direct_post.id }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('private')
    end

    it 'never renders the publicly cached embed for non-public posts, even for the author' do
      session[:current_user_id] = owner.id

      get :embed, params: { username: owner.username, id: direct_post.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for the ActivityPub representation of a DM' do
      request.headers['Accept'] = 'application/activity+json'

      get :redirect_to_frontend, params: { username: owner.username, id: direct_post.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe ObjectsController, type: :controller do
    before { request.headers['Accept'] = 'application/activity+json' }

    it 'serves public posts' do
      get :show, params: { username: owner.username, id: public_post.id }

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for followers-only posts and DMs' do
      [private_post, direct_post].each do |post|
        get :show, params: { username: owner.username, id: post.id }
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'does not serve objects received from other servers' do
      remote = create(:activity_pub_object, :note, :remote, actor: create(:actor, :remote), visibility: 'public')

      get :show, params: { username: owner.username, id: remote.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'requires the URL username to match the author' do
      other = create(:actor, username: 'someone', local: true)

      get :show, params: { username: other.username, id: public_post.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe ActivitiesController, type: :controller do
    before { request.headers['Accept'] = 'application/activity+json' }

    it 'serves the Create activity of a public post' do
      activity = create(:activity, actor: owner, object_ap_id: public_post.ap_id)

      get :show, params: { id: activity.id }

      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for the Create activity of a DM' do
      activity = create(:activity, actor: owner, object_ap_id: direct_post.ap_id)

      get :show, params: { id: activity.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'does not serve activities received from other servers' do
      activity = create(:activity, :remote, actor: create(:actor, :remote), object_ap_id: public_post.ap_id)

      get :show, params: { id: activity.id }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe FeedsController, type: :controller do
    render_views

    before do
      public_post.update!(content: '<p>public-entry</p>')
      unlisted_post.update!(content: '<p>unlisted-entry</p>')
      private_post.update!(content: '<p>private-entry</p>')
      direct_post.update!(content: '<p>direct-entry</p>')
    end

    it 'lists only public posts in the local Atom feed' do
      get :local, format: :atom

      expect(response.body).to include('public-entry')
      expect(response.body).not_to include('unlisted-entry', 'private-entry', 'direct-entry')
    end

    it 'lists public and unlisted posts in the user RSS feed' do
      get :user, params: { username: owner.username }, format: :rss

      expect(response.body).to include('public-entry', 'unlisted-entry')
      expect(response.body).not_to include('private-entry', 'direct-entry')
    end
  end
end
