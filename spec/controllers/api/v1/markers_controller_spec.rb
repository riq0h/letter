# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::MarkersController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write', expires_in: 2.hours)
  end

  before { request.headers['Authorization'] = "Bearer #{access_token.token}" }

  def marker_value(timeline)
    user.markers.for_timeline(timeline).first&.last_read_id
  end

  describe 'POST #create' do
    it '初回POSTでマーカーを作成する' do
      post :create, params: { notifications: { last_read_id: '100' } }

      expect(response).to have_http_status(:ok)
      expect(marker_value('notifications')).to eq('100')
      expect(response.parsed_body.dig('notifications', 'last_read_id')).to eq('100')
    end

    it 'より新しいIDには前進する' do
      Marker.create!(actor: user, timeline: 'notifications', last_read_id: '100', version: 1)

      post :create, params: { notifications: { last_read_id: '250' } }

      expect(marker_value('notifications')).to eq('250')
    end

    it '古いIDをPOSTされても後退しない（数値比較）' do
      Marker.create!(actor: user, timeline: 'notifications', last_read_id: '358020', version: 1)

      # 辞書順だと "9" > "358020" になるが、数値比較なので後退させない
      post :create, params: { notifications: { last_read_id: '9' } }

      expect(marker_value('notifications')).to eq('358020')
      # レスポンスは権威ある(より新しい)位置を返し、クライアントの同期を促す
      expect(response.parsed_body.dig('notifications', 'last_read_id')).to eq('358020')
    end

    it '前進時に確定した既読位置以下の通知を既読化する' do
      other = create(:actor, local: true)
      n1 = create(:notification, account: user, from_account: other, notification_type: 'follow')
      n2 = create(:notification, account: user, from_account: other, notification_type: 'follow')

      post :create, params: { notifications: { last_read_id: n2.id.to_s } }

      expect(n1.reload.read).to be true
      expect(n2.reload.read).to be true
    end

    it '後退POSTでは既読済みを未読に戻さない' do
      other = create(:actor, local: true)
      n1 = create(:notification, account: user, from_account: other, notification_type: 'follow', read: true)
      Marker.create!(actor: user, timeline: 'notifications', last_read_id: (n1.id + 100).to_s, version: 1)

      post :create, params: { notifications: { last_read_id: '1' } }

      expect(n1.reload.read).to be true
    end

    it 'homeマーカー（Snowflake文字列ID）も後退させない' do
      Marker.create!(actor: user, timeline: 'home', last_read_id: '21301966546880511', version: 1)

      post :create, params: { home: { last_read_id: '100' } }

      expect(marker_value('home')).to eq('21301966546880511')
    end
  end
end
