# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubFollowHandlers, type: :controller do
  controller(ApplicationController) do
    include ActivityPubFollowHandlers

    # CSRFトークン無効化（テスト用）
    skip_before_action :verify_authenticity_token

    def test_undo_action
      @activity = params[:activity]
      @sender = params[:sender]
      handle_undo_activity
    end
  end

  let(:local_actor) { create(:actor) }
  let(:remote_actor) { create(:actor, :remote) }
  let(:status) { create(:activity_pub_object, actor: local_actor) }
  let!(:favourite) { create(:favourite, actor: remote_actor, object: status) }
  let!(:reblog) { create(:reblog, actor: remote_actor, object: status) }

  before do
    routes.draw { post 'test_undo_action' => 'anonymous#test_undo_action' }
    allow(controller.request).to receive(:base_url).and_return('https://letter.test')
  end

  describe '#handle_undo_like' do
    let(:undo_like_activity) do
      {
        '@context' => 'https://www.w3.org/ns/activitystreams',
        'type' => 'Undo',
        'actor' => remote_actor.ap_id,
        'object' => {
          'type' => 'Like',
          'actor' => remote_actor.ap_id,
          'object' => status.ap_id
        }
      }
    end

    it 'successfully removes like activity and favourite' do
      # テスト用のLikeアクティビティを作成
      create(:activity, actor: remote_actor, activity_type: 'Like', object: status)
      expect do
        post :test_undo_action, params: { activity: undo_like_activity, sender: remote_actor }
      end.to change(Favourite, :count).by(-1)
                                      .and change { Activity.where(activity_type: 'Like').count }.by(-1)

      expect(response).to have_http_status(:accepted)
    end

    it 'decrements favourites_count on the object' do
      initial_count = status.favourites_count

      post :test_undo_action, params: { activity: undo_like_activity, sender: remote_actor }

      expect(status.reload.favourites_count).to eq(initial_count - 1)
    end

    it 'handles missing favourite gracefully' do
      favourite.destroy!

      expect do
        post :test_undo_action, params: { activity: undo_like_activity, sender: remote_actor }
      end.not_to(change(Favourite, :count))

      expect(response).to have_http_status(:accepted)
    end

    it 'handles missing target object gracefully' do
      undo_like_activity['object']['object'] = 'https://example.com/nonexistent'

      expect do
        post :test_undo_action, params: { activity: undo_like_activity, sender: remote_actor }
      end.not_to(change(Favourite, :count))

      expect(response).to have_http_status(:accepted)
    end
  end

  describe '#handle_undo_announce' do
    let(:undo_announce_activity) do
      {
        '@context' => 'https://www.w3.org/ns/activitystreams',
        'type' => 'Undo',
        'actor' => remote_actor.ap_id,
        'object' => {
          'type' => 'Announce',
          'actor' => remote_actor.ap_id,
          'object' => status.ap_id
        }
      }
    end

    it 'successfully removes announce activity and reblog' do
      # テスト用のAnnounceアクティビティを作成
      create(:activity, actor: remote_actor, activity_type: 'Announce', object: status)
      expect do
        post :test_undo_action, params: { activity: undo_announce_activity, sender: remote_actor }
      end.to change(Reblog, :count).by(-1)
                                   .and change { Activity.where(activity_type: 'Announce').count }.by(-1)

      expect(response).to have_http_status(:accepted)
    end

    it 'decrements reblogs_count on the object' do
      initial_count = status.reblogs_count

      post :test_undo_action, params: { activity: undo_announce_activity, sender: remote_actor }

      expect(status.reload.reblogs_count).to eq(initial_count - 1)
    end

    it 'handles missing reblog gracefully' do
      reblog.destroy!

      expect do
        post :test_undo_action, params: { activity: undo_announce_activity, sender: remote_actor }
      end.not_to(change(Reblog, :count))

      expect(response).to have_http_status(:accepted)
    end

    it 'handles missing target object gracefully' do
      undo_announce_activity['object']['object'] = 'https://example.com/nonexistent'

      expect do
        post :test_undo_action, params: { activity: undo_announce_activity, sender: remote_actor }
      end.not_to(change(Reblog, :count))

      expect(response).to have_http_status(:accepted)
    end
  end
end
