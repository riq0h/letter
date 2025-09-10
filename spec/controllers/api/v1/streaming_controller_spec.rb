# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::StreamingController, type: :controller do
  let(:user) { create(:actor, local: true) }
  let(:access_token) do
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
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
        expect(response.parsed_body).to eq([])
      end

      it 'returns user timeline events' do
        # ユーザの投稿を作成
        create(:activity_pub_object, actor: user, object_type: 'Note', visibility: 'public')

        get :index, params: { stream: 'user', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = response.parsed_body
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'returns public timeline events' do
        create(:activity_pub_object, object_type: 'Note', visibility: 'public')

        get :index, params: { stream: 'public', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = response.parsed_body
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'returns local timeline events' do
        local_actor = create(:actor, local: true)
        create(:activity_pub_object, actor: local_actor, object_type: 'Note', visibility: 'public', local: true)

        get :index, params: { stream: 'public:local', since_id: 0 }

        expect(response).to have_http_status(:ok)
        events = response.parsed_body
        expect(events).not_to be_empty
        expect(events.first['event']).to eq('update')
      end

      it 'filters events by since_id' do
        # ID 100より小さい投稿
        create(:activity_pub_object, id: 50, object_type: 'Note', visibility: 'public')
        # ID 100より大きい投稿
        create(:activity_pub_object, id: 150, object_type: 'Note', visibility: 'public')

        get :index, params: { stream: 'public', since_id: 100 }

        expect(response).to have_http_status(:ok)
        events = response.parsed_body

        # since_id=100より大きいIDのイベントのみ返される
        returned_ids = events.map { |e| JSON.parse(e['payload'])['id'].to_i }
        expect(returned_ids).to include(150)
        expect(returned_ids).not_to include(50)
      end
    end

    context 'with SSE request' do
      before do
        request.headers['Accept'] = 'text/event-stream'
      end

      it 'sets proper SSE headers' do
        # SSEはストリーミングなのでタイムアウト設定
        allow(controller).to receive(:subscribe_to_streams).and_return(nil)

        get :index, params: { stream: 'user' }

        expect(response.headers['Content-Type']).to eq('text/event-stream')
        expect(response.headers['Cache-Control']).to eq('no-cache')
        expect(response.headers['Connection']).to eq('keep-alive')
      end
    end

    context 'with invalid stream type' do
      it 'returns empty array for HTTP polling' do
        get :index, params: { stream: 'invalid', since_id: 0 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq([])
      end
    end

    context 'without authentication' do
      before do
        request.headers.delete('Authorization')
      end

      it 'returns unauthorized' do
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
      events = response.parsed_body
      expect(events).not_to be_empty
      expect(events.first['event']).to eq('update')
    end

    it 'returns empty array for non-existent hashtag' do
      get :index, params: { stream: 'hashtag', tag: 'nonexistent', since_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end

  describe 'list stream' do
    it 'returns list events' do
      list = create(:list, owner: user)
      member = create(:actor, local: true)
      create(:list_membership, list: list, actor: member)
      create(:activity_pub_object, actor: member, object_type: 'Note')

      get :index, params: { stream: "list:#{list.id}", since_id: 0 }

      expect(response).to have_http_status(:ok)
      events = response.parsed_body
      expect(events).not_to be_empty
      expect(events.first['event']).to eq('update')
    end

    it 'returns empty array for non-existent list' do
      get :index, params: { stream: 'list:99999', since_id: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
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
