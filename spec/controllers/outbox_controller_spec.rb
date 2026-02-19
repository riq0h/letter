# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OutboxController, type: :controller do
  let(:actor) { create(:actor, username: 'testuser', local: true) }

  before do
    request.headers['Accept'] = 'application/activity+json'
  end

  # ActivityPubObjectを作成し、自動生成されたCreate Activityを返す
  def create_public_activity(actor:, visibility: 'public')
    obj = create(:activity_pub_object, actor: actor, visibility: visibility, local: true)
    Activity.find_by(object_ap_id: obj.ap_id, activity_type: 'Create')
  end

  def parse_json
    JSON.parse(response.body) # rubocop:disable Rails/ResponseParsedBody
  end

  describe 'GET #show' do
    context 'without page parameter (collection summary)' do
      it 'returns OrderedCollection with totalItems and pagination links' do
        3.times { create_public_activity(actor: actor) }
        create_public_activity(actor: actor, visibility: 'unlisted')

        get :show, params: { username: actor.username }

        expect(response).to have_http_status(:ok)
        json = parse_json
        expect(json['type']).to eq('OrderedCollection')
        expect(json['totalItems']).to eq(4)
        expect(json['first']).to include('page=true')
        expect(json['last']).to include('page=true', 'min_id=0')
        expect(json).not_to have_key('orderedItems')
      end

      it 'excludes private and direct activities from totalItems' do
        create_public_activity(actor: actor)
        create_public_activity(actor: actor, visibility: 'private')
        create_public_activity(actor: actor, visibility: 'direct')

        get :show, params: { username: actor.username }

        json = parse_json
        expect(json['totalItems']).to eq(1)
      end

      it 'excludes non-Create activities from totalItems' do
        create_public_activity(actor: actor)
        create(:activity, :follow, actor: actor)
        create(:activity, :like, actor: actor)

        get :show, params: { username: actor.username }

        json = parse_json
        expect(json['totalItems']).to eq(1)
      end
    end

    context 'with page parameter (collection page)' do
      it 'returns OrderedCollectionPage with activities' do
        3.times { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true' }

        expect(response).to have_http_status(:ok)
        json = parse_json
        expect(json['type']).to eq('OrderedCollectionPage')
        expect(json['partOf']).to eq(actor.outbox_url)
        expect(json['orderedItems'].size).to eq(3)
      end

      it 'includes next link when page is full' do
        21.times { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true' }

        json = parse_json
        expect(json['orderedItems'].size).to eq(20)
        expect(json['next']).to include('max_id=')
      end

      it 'does not include next link when page is not full' do
        5.times { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true' }

        json = parse_json
        expect(json['orderedItems'].size).to eq(5)
        expect(json).not_to have_key('next')
      end

      it 'returns prev link when max_id is specified' do
        activities = Array.new(5) { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true', max_id: activities.last.id }

        json = parse_json
        expect(json).to have_key('prev')
        expect(json['prev']).to include('min_id=')
      end

      it 'paginates with max_id' do
        activities = Array.new(5) { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true', max_id: activities[2].id }

        json = parse_json
        expect(json['orderedItems'].size).to be <= 2
      end

      it 'does not include prev link on first page' do
        3.times { create_public_activity(actor: actor) }

        get :show, params: { username: actor.username, page: 'true' }

        json = parse_json
        expect(json).not_to have_key('prev')
      end
    end

    context 'when actor does not exist' do
      it 'returns 404' do
        get :show, params: { username: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
