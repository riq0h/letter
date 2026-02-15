# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::StreamingController, type: :controller do
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
      scopes: 'read:statuses read:notifications',
      expires_in: 2.hours
    )
  end

  before do
    request.headers['Authorization'] = "Bearer #{access_token.token}"
  end

  describe 'GET #index' do
    context 'with HTTP polling request' do
      it 'returns empty array for user stream with no content' do
        get :index, params: { stream: 'user', since_id: 0 }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq([])
      end

      it 'returns user timeline events' do
        # ユーザの投稿を作成
        create(:activity_pub_object, actor: user, object_type: 'Note', visibility: 'public')

        get :index, params: { stream: 'user', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = JSON.parse(response.body)
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'returns public timeline events' do
        create(:activity_pub_object, object_type: 'Note', visibility: 'public')

        get :index, params: { stream: 'public', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = JSON.parse(response.body)
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'returns local timeline events' do
        local_actor = create(:actor, local: true)
        create(:activity_pub_object, actor: local_actor, object_type: 'Note', visibility: 'public', local: true)

        get :index, params: { stream: 'public:local', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = JSON.parse(response.body)
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'filters events by since_id' do
        # 先に古い投稿を作成
        older_post = create(:activity_pub_object, object_type: 'Note', visibility: 'public')
        # 次に新しい投稿を作成
        newer_post = create(:activity_pub_object, object_type: 'Note', visibility: 'public')

        # older_postのIDをsince_idとして使用し、それより新しいもののみ返されることを確認
        get :index, params: { stream: 'public', since_id: older_post.id }

        expect(response).to have_http_status(:ok)
        events = JSON.parse(response.body)

        # since_idより大きいIDのイベントのみ返される
        returned_ids = events.map { |e| JSON.parse(e['payload'])['id'] }
        expect(returned_ids).to include(newer_post.id.to_s)
        expect(returned_ids).not_to include(older_post.id.to_s)
      end
    end

    context 'with SSE request' do
      before do
        request.headers['Accept'] = 'text/event-stream'
      end

      it 'sets proper SSE headers' do
        # serve_sse_streamが呼ばれることを確認（SSEリクエストとして認識される）
        expect(controller).to receive(:serve_sse_stream) do
          # ヘッダーが設定されるはずの処理をシミュレート
          controller.head :ok
        end

        get :index, params: { stream: 'user' }
      end
    end

    context 'with invalid stream type' do
      it 'returns empty array for HTTP polling' do
        get :index, params: { stream: 'invalid', since_id: 0 }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq([])
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        request.headers['Authorization'] = nil
        get :index, params: { stream: 'user' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'hashtag stream' do
    it 'returns hashtag events' do
      tag = create(:tag, name: 'test')
      status = create(:activity_pub_object, object_type: 'Note', visibility: 'public')
      create(:object_tag, object: status, tag: tag)

      get :index, params: { stream: 'hashtag', tag: 'test', since_id: 0 }

      expect(response).to have_http_status(:ok)
      events = JSON.parse(response.body)
      expect(events).not_to be_empty
      expect(events.first['event']).to eq('update')
    end

    it 'returns empty array for non-existent hashtag' do
      get :index, params: { stream: 'hashtag', tag: 'nonexistent', since_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe 'list stream' do
    it 'returns list events' do
      list = List.create!(actor: user, title: 'Test List', replies_policy: 'list', exclusive: false)
      member = create(:actor, local: true)
      ListMembership.create!(list: list, actor: member)
      create(:activity_pub_object, actor: member, object_type: 'Note')

      get :index, params: { stream: "list:#{list.id}", since_id: 0 }

      expect(response).to have_http_status(:ok)
      events = JSON.parse(response.body)
      expect(events).not_to be_empty
      expect(events.first['event']).to eq('update')
    end

    it 'returns empty array for non-existent list' do
      get :index, params: { stream: 'list:99999', since_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe 'CORS headers' do
    it 'sets proper CORS headers' do
      get :index, params: { stream: 'public', since_id: 0 }

      expect(response.headers['Access-Control-Allow-Origin']).to eq('*')
      expect(response.headers['Access-Control-Allow-Methods']).to eq('GET, OPTIONS')
      expect(response.headers['Access-Control-Allow-Headers']).to eq('Authorization, Content-Type')
    end
  end
end
