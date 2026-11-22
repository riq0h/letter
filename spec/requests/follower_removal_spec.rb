# frozen_string_literal: true

require 'rails_helper'

# フォロワーから外す・フォローリクエストを断るときは、相手のサーバにも伝える
RSpec.describe 'Removing followers', type: :request do
  let(:user) { create(:actor) }
  let(:follower) { create(:actor, :remote) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write follow', expires_in: 2.hours)
  end
  let(:auth) { { 'Authorization' => "Bearer #{access_token.token}" } }

  it 'removes a follower and tells its server' do
    follow = create(:follow, actor: follower, target_actor: user, accepted: true)

    expect do
      post "/api/v1/accounts/#{follower.id}/remove_from_followers", headers: auth
    end.to have_enqueued_job(SendRejectFollowJob).with(user.id, follower.id, follow.follow_activity_ap_id)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['followed_by']).to be false
    expect(Follow.exists?(follow.id)).to be false
  end

  it 'tells the server when a follow request is rejected' do
    request = create(:follow, actor: follower, target_actor: user, accepted: false)

    expect do
      post "/api/v1/follow_requests/#{request.id}/reject", headers: auth
    end.to have_enqueued_job(SendRejectFollowJob).with(user.id, follower.id, request.follow_activity_ap_id)

    expect(Follow.exists?(request.id)).to be false
  end

  describe SendRejectFollowJob do
    it 'sends a Reject with the follow it refers to' do
      sender = instance_double(ActivitySender)
      allow(ActivitySender).to receive(:new).and_return(sender)
      allow(sender).to receive(:send_activity).and_return(success: true)

      described_class.perform_now(user.id, follower.id, 'https://remote.example.com/follows/1')

      expect(sender).to have_received(:send_activity).with(
        activity: hash_including('type' => 'Reject', 'actor' => user.ap_id,
                                 'object' => { 'id' => 'https://remote.example.com/follows/1', 'type' => 'Follow',
                                               'actor' => follower.ap_id, 'object' => user.ap_id }),
        target_inbox: follower.inbox_url, signing_actor: user
      )
    end
  end
end
