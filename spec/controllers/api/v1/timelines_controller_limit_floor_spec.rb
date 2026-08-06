# frozen_string_literal: true

require 'rails_helper'

# タイムラインlimit下限フロア: Moshidon等はlimit=20固定で送るため、
# 設定(timeline_limit_floor)で1回の読み込み件数をサーバ側から引き上げる
RSpec.describe Api::V1::TimelinesController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:application) do
    Doorkeeper::Application.create!(name: 'Test App', redirect_uri: 'https://localhost', confidential: false)
  end
  let(:access_token) do
    Doorkeeper::AccessToken.create!(resource_owner_id: user.id, application: application,
                                    scopes: 'read write', expires_in: 2.hours)
  end

  def stub_home_query
    query = instance_double(TimelineQuery, build_home_timeline: [])
    captured = nil
    allow(TimelineQuery).to receive(:new) do |_u, p|
      captured = p
      query
    end
    -> { captured }
  end

  context 'when authenticated' do
    before { request.headers['Authorization'] = "Bearer #{access_token.token}" }

    it 'keeps the requested limit when floor is unset (default 0)' do
      captured = stub_home_query
      get :home, params: { limit: '20' }

      expect(captured.call[:limit]).to eq(20)
    end

    it 'raises the effective limit to the configured floor (limit=20 -> 200)' do
      InstanceConfig.set('timeline_limit_floor', '200')
      captured = stub_home_query

      get :home, params: { limit: '20' }

      expect(captured.call[:limit]).to eq(200)
    end

    it 'respects a client limit above the floor cap chain' do
      InstanceConfig.set('timeline_limit_floor', '30')
      captured = stub_home_query

      get :home, params: { limit: '40' }

      expect(captured.call[:limit]).to eq(40)
    end
  end

  context 'when anonymous (public timeline)' do
    it 'does not apply the floor to unauthenticated requests' do
      InstanceConfig.set('timeline_limit_floor', '200')
      query = instance_double(TimelineQuery, build_public_timeline: [])
      captured = nil
      allow(TimelineQuery).to receive(:new) do |_u, p|
        captured = p
        query
      end

      get :public, params: { limit: '20' }

      expect(captured[:limit]).to eq(20)
    end
  end
end
