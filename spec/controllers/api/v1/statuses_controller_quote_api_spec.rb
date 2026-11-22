# frozen_string_literal: true

require 'rails_helper'

# Mastodon 4.5公式の引用API互換:
# - POST /api/v1/statuses の quoted_status_id を既存QuotePost機構へマッピング
# - Statusエンティティの quote は公式形({state:, quoted_status:})、quotes_count・quote_approval付き
# - 投稿ごとの引用の許可設定(quote_approval_policy)と、その変更(PUT interaction_policy)
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

    it 'federates the quote only through the Create of the new post' do
      post :create, params: { status: '引用', quoted_status_id: quoted.id }

      status = ActivityPubObject.find(response.parsed_body['id'])
      expect(Activity.where(activity_type: 'Create', object_ap_id: status.ap_id).count).to eq(1)
      expect(Activity.where(activity_type: 'Create', object_ap_id: nil)).to be_empty
    end

    it 'refuses to quote a post whose author lets nobody quote it' do
      quoted.update!(quote_policy: 'nobody')

      post :create, params: { status: '引用', quoted_status_id: quoted.id }

      expect(response).to have_http_status(:unprocessable_content)
      expect(QuotePost.count).to eq(0)
    end

    it 'does not quote posts the user cannot see' do
      hidden = create(:activity_pub_object, :note, actor: other, visibility: 'private')

      post :create, params: { status: '引用', quoted_status_id: hidden.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'reports a quote as pending until the author server approves it' do
      author = create(:actor, :remote)
      remote = create(:activity_pub_object, :remote, actor: author,
                                                     raw_data: { 'interactionPolicy' => { 'canQuote' => {
                                                       'automaticApproval' => ['https://www.w3.org/ns/activitystreams#Public']
                                                     } } }.to_json)

      post :create, params: { status: '他サーバの投稿を引用', quoted_status_id: remote.id }

      expect(response.parsed_body['quote']).to eq('state' => 'pending', 'quoted_status' => nil)
    end
  end

  describe 'quote policies' do
    it 'tells the client who may quote a post' do
      get :show, params: { id: quoted.id }

      expect(response.parsed_body['quote_approval']).to eq('automatic' => ['public'], 'manual' => [],
                                                           'current_user' => 'automatic')
    end

    it 'stores the policy chosen when posting' do
      post :create, params: { status: 'フォロワーだけ引用できる', quote_approval_policy: 'followers' }

      expect(ActivityPubObject.find(response.parsed_body['id']).quote_policy).to eq('followers')
      expect(response.parsed_body['quote_approval']['automatic']).to eq(['followers'])
    end

    it 'uses the default policy from the settings when none is chosen' do
      user.update_setting('posting:default:quote_policy', 'nobody')

      post :create, params: { status: '既定の設定' }

      expect(ActivityPubObject.find(response.parsed_body['id']).quote_policy).to eq('nobody')
    end

    it 'lets nobody quote followers-only posts' do
      post :create, params: { status: 'フォロワー限定', visibility: 'private', quote_approval_policy: 'public' }

      expect(ActivityPubObject.find(response.parsed_body['id']).quote_policy).to eq('nobody')
    end

    it 'changes the policy of an existing post and tells other servers' do
      mine = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      expect do
        put :interaction_policy, params: { id: mine.id, quote_approval_policy: 'nobody' }
      end.to change { Activity.where(activity_type: 'Update', object_ap_id: mine.ap_id).count }.by(1)

      expect(mine.reload.quote_policy).to eq('nobody')
      expect(response.parsed_body['quote_approval']['automatic']).to eq([])
    end

    it 'does not let others change the policy' do
      put :interaction_policy, params: { id: quoted.id, quote_approval_policy: 'nobody' }

      expect(response).to have_http_status(:forbidden)
      expect(quoted.reload.quote_policy).to be_nil
    end

    it 'changes the policy when the post is edited' do
      mine = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      put :update, params: { id: mine.id, status: '編集', quote_approval_policy: 'followers' }

      expect(mine.reload.quote_policy).to eq('followers')
    end
  end

  describe 'POST #revoke_quote' do
    let(:quoter) { create(:actor, :remote) }
    let(:mine) { create(:activity_pub_object, :note, actor: user, visibility: 'public') }
    let(:quoting) { create(:activity_pub_object, :remote, actor: quoter) }
    let!(:quote_post) { QuotePost.create!(actor: quoter, object: quoting, quoted_object: mine, ap_id: "#{quoting.ap_id}#quote") }

    it 'withdraws the approval and tells the quoting server and our followers' do
      follower = create(:actor, :remote)
      create(:follow, actor: follower, target_actor: user, accepted: true)
      authorization_uri = quote_post.quote_authorization.ap_id

      expect do
        post :revoke_quote, params: { id: mine.id, quoting_status_id: quoting.id }
      end.to have_enqueued_job(SendActivityJob).with(anything, array_including(quoter.preferred_inbox, follower.preferred_inbox))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(quoting.id.to_s)
      expect(response.parsed_body['quote']).to be_nil
      expect(QuotePost.exists?(quote_post.id)).to be false
      expect(QuoteAuthorization.exists?(ap_id: authorization_uri)).to be false
      expect(Activity.find_by(activity_type: 'Delete', target_ap_id: authorization_uri)).to be_present
    end

    it 'does not let others revoke quotes of posts that are not theirs' do
      theirs = create(:activity_pub_object, :note, actor: other, visibility: 'public')
      QuotePost.create!(actor: quoter, object: quoting, quoted_object: theirs, ap_id: "#{quoting.ap_id}#quote2")

      post :revoke_quote, params: { id: theirs.id, quoting_status_id: quoting.id }

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for a post that does not quote this one' do
      post :revoke_quote, params: { id: mine.id, quoting_status_id: create(:activity_pub_object, :remote).id }

      expect(response).to have_http_status(:not_found)
      expect(QuotePost.exists?(quote_post.id)).to be true
    end
  end

  describe 'POST #quote (letter endpoint)' do
    it 'quotes the post like quoted_status_id does' do
      post :quote, params: { id: quoted.id, status: 'こちらでも引用' }

      expect(response).to have_http_status(:created)
      status = ActivityPubObject.find(response.parsed_body['id'])
      expect(status.ap_id).to end_with("/users/#{user.username}/posts/#{status.id}")
      expect(QuotePost.find_by(object: status).quoted_object).to eq(quoted)
      expect(Activity.where(activity_type: 'Create', object_ap_id: status.ap_id)).to exist
    end
  end

  describe 'scheduled quotes' do
    it 'quotes the post when the scheduled status is published' do
      post :create, params: { status: '予約した引用', quoted_status_id: quoted.id, quote_approval_policy: 'followers',
                              scheduled_at: 1.hour.from_now.iso8601 }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['params']['quoted_status_id']).to eq(quoted.id.to_s)

      status = ScheduledStatus.last.publish!
      expect(QuotePost.find_by(object: status).quoted_object).to eq(quoted)
      expect(status.quote_policy).to eq('followers')
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
