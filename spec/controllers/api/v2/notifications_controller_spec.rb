# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V2::NotificationsController, type: :controller do
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
    it 'returns grouped notifications' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :index

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json).to have_key('accounts')
      expect(json).to have_key('statuses')
      expect(json).to have_key('notification_groups')
      expect(json['notification_groups'].length).to eq(1)
    end

    it 'groups notifications by type and status' do
      status = create(:activity_pub_object, :note, actor: user)
      user1 = create(:actor, local: true)
      user2 = create(:actor, local: true)

      create(:notification, account: user, from_account: user1,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)
      create(:notification, account: user, from_account: user2,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :index

      json = response.parsed_body
      groups = json['notification_groups']
      # 同じステータスへのfavouriteは1グループにまとまる
      fav_groups = groups.select { |g| g['type'] == 'favourite' }
      expect(fav_groups.length).to eq(1)
      expect(fav_groups.first['notifications_count']).to eq(2)
      expect(fav_groups.first['sample_account_ids'].length).to eq(2)
    end

    it 'includes accounts and statuses in separate keys' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'mention', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :index

      json = response.parsed_body
      account_ids = json['accounts'].pluck('id')
      status_ids = json['statuses'].pluck('id')
      expect(account_ids).to include(other_user.id.to_s)
      expect(status_ids).to include(status.id.to_s)
    end

    it 'filters by types' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'mention', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :index, params: { types: ['favourite'] }

      json = response.parsed_body
      types = json['notification_groups'].pluck('type')
      expect(types).to include('favourite')
      expect(types).not_to include('mention')
    end

    it 'filters by exclude_types' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'mention', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :index, params: { exclude_types: ['favourite'] }

      json = response.parsed_body
      types = json['notification_groups'].pluck('type')
      expect(types).not_to include('favourite')
      expect(types).to include('mention')
    end

    it 'requires authentication' do
      request.headers['Authorization'] = nil

      get :index

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET #unread_count' do
    it 'returns unread count based on marker' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      n1 = create(:notification, account: user, from_account: other_user,
                                 notification_type: 'favourite', activity_type: 'ActivityPubObject',
                                 activity_id: status.id.to_s)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'mention', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      # マーカーで最初の通知まで既読とする
      Marker.create!(actor: user, timeline: 'notifications', last_read_id: n1.id, version: 1)

      get :unread_count

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['count']).to eq(1)
    end

    it 'returns all notifications count when no marker exists' do
      other_user = create(:actor, local: true)
      status = create(:activity_pub_object, :note, actor: user)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'favourite', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)
      create(:notification, account: user, from_account: other_user,
                            notification_type: 'mention', activity_type: 'ActivityPubObject',
                            activity_id: status.id.to_s)

      get :unread_count

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['count']).to eq(2)
    end
  end
end
