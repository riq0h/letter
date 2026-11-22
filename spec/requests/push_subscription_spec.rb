# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Push subscriptions', type: :request do
  let(:user) { create(:actor) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Push Client', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write follow push', use_refresh_token: true)
  end
  let(:auth) { { 'Authorization' => "Bearer #{access_token.token}" } }
  let(:p256dh) do
    Base64.urlsafe_encode64(OpenSSL::PKey::EC.generate('prime256v1').public_key.to_bn.to_s(2), padding: false)
  end
  let(:auth_secret) { Base64.urlsafe_encode64(SecureRandom.random_bytes(16), padding: false) }

  def subscription_body(alerts)
    { subscription: { endpoint: 'https://push.example/relay-to/fcm/device/account', keys: { p256dh: p256dh, auth: auth_secret } },
      data: { alerts: alerts } }
  end

  describe 'POST /api/v1/push/subscription' do
    it 'registers the subscription sent as JSON' do
      post '/api/v1/push/subscription',
           params: subscription_body(mention: true, quote: true, favourite: false).to_json,
           headers: auth.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:created)
      subscription = WebPushSubscription.find_by(access_token_id: access_token.id)
      expect(subscription.alerts).to include('mention' => true, 'quote' => true, 'favourite' => false)
      expect(response.parsed_body['alerts']).to include('mention' => true, 'favourite' => false)
    end

    it 'reads alerts sent as form strings as true and false' do
      post '/api/v1/push/subscription',
           params: subscription_body(mention: 'true', favourite: 'false', admin: { sign_up: 'true' }),
           headers: auth

      alerts = WebPushSubscription.find_by(access_token_id: access_token.id).alerts
      expect(alerts).to include('mention' => true, 'favourite' => false, 'admin.sign_up' => true)
      expect(alerts).not_to have_key('admin')
    end
  end

  describe 'unsubscribing from the push service' do
    let!(:subscription) { create(:web_push_subscription, actor: user, access_token: access_token) }

    it 'removes the subscription named by the unsubscribe URL' do
      delete URI.parse(subscription.unsubscribe_url).path

      expect(response).to have_http_status(:ok)
      expect(WebPushSubscription.exists?(subscription.id)).to be false
    end

    it 'ignores an unknown token' do
      delete '/api/web/push_subscriptions/not-a-token'

      expect(response).to have_http_status(:ok)
      expect(WebPushSubscription.exists?(subscription.id)).to be true
    end
  end

  describe 'tokens and subscriptions' do
    let!(:subscription) { create(:web_push_subscription, actor: user, access_token: access_token) }

    it 'removes the subscription when the client logs out' do
      post '/oauth/revoke', params: { token: access_token.token, client_id: application.uid,
                                      client_secret: application.secret }

      expect(response).to have_http_status(:ok)
      expect(access_token.reload).to be_revoked
      expect(WebPushSubscription.exists?(subscription.id)).to be false
    end

    it 'moves the subscription to a refreshed token' do
      post '/oauth/token', params: { grant_type: 'refresh_token', refresh_token: access_token.refresh_token,
                                     client_id: application.uid, client_secret: application.secret }

      expect(response).to have_http_status(:ok)
      new_token = Doorkeeper::AccessToken.find_by(token: response.parsed_body['access_token'])
      expect(subscription.reload.access_token_id).to eq(new_token.id)
    end
  end
end
