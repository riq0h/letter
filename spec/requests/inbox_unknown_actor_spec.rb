# frozen_string_literal: true

require 'rails_helper'

# 未知のアクターが自分自身を対象に送るDelete/Updateは、署名検証(鍵の取得)をせずに202で捨てる
RSpec.describe 'Inbox activities from unknown actors', type: :request do
  let(:gone_uri) { 'https://gone.example/users/deleted' }
  let(:headers) { { 'Content-Type' => 'application/activity+json' } }

  def activity(type, actor:, object:)
    { '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => "#{actor}#delete", 'type' => type, 'actor' => actor, 'object' => object }.to_json
  end

  describe 'POST /inbox' do
    it 'accepts a self Delete from an unknown actor without fetching its key' do
      expect(HttpSignatureVerifier).not_to receive(:new)

      post '/inbox', params: activity('Delete', actor: gone_uri, object: gone_uri), headers: headers

      expect(response).to have_http_status(:accepted)
      expect(Actor.exists?(ap_id: gone_uri)).to be false
    end

    it 'accepts a self Update from an unknown actor given as an embedded object' do
      expect(HttpSignatureVerifier).not_to receive(:new)

      post '/inbox', params: activity('Update', actor: gone_uri, object: { 'id' => gone_uri, 'type' => 'Person' }),
                     headers: headers

      expect(response).to have_http_status(:accepted)
    end

    it 'still requires a signature when the actor is already known' do
      known = create(:actor, :remote)

      post '/inbox', params: activity('Delete', actor: known.ap_id, object: known.ap_id), headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(known.reload).to be_present
    end

    it 'still requires a signature when an unknown actor deletes something other than itself' do
      post '/inbox', params: activity('Delete', actor: gone_uri, object: 'https://gone.example/notes/1'),
                     headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'still requires a signature for other activity types from an unknown actor' do
      post '/inbox', params: activity('Follow', actor: gone_uri, object: gone_uri), headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /users/:username/inbox' do
    let(:local_actor) { create(:actor) }

    it 'accepts a self Delete from an unknown actor without fetching its key' do
      expect(HttpSignatureVerifier).not_to receive(:new)

      post "/users/#{local_actor.username}/inbox",
           params: activity('Delete', actor: gone_uri, object: gone_uri), headers: headers

      expect(response).to have_http_status(:accepted)
    end
  end
end
