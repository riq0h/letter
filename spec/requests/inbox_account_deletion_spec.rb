# frozen_string_literal: true

require 'rails_helper'

# 既知のアカウントが自分自身を対象に送るDeleteは、アカウントの削除として扱う
RSpec.describe 'Account deletion from a remote server', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end

  def delete_activity(object)
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}#delete",
      'type' => 'Delete', 'actor' => remote.ap_id, 'object' => object }.to_json
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  describe 'POST /inbox' do
    it 'schedules deleting the account when it deletes itself' do
      expect { post '/inbox', params: delete_activity(remote.ap_id), headers: headers }
        .to have_enqueued_job(DeleteRemoteActorJob).with(remote.id)

      expect(response).to have_http_status(:accepted)
    end

    it 'accepts the account given as an embedded object' do
      expect { post '/inbox', params: delete_activity({ 'id' => remote.ap_id, 'type' => 'Person' }), headers: headers }
        .to have_enqueued_job(DeleteRemoteActorJob).with(remote.id)
    end

    it 'deletes only the post when one of its posts is deleted' do
      note = create(:activity_pub_object, :remote, actor: remote)

      expect { post '/inbox', params: delete_activity(note.ap_id), headers: headers }
        .not_to have_enqueued_job(DeleteRemoteActorJob)

      expect(ActivityPubObject.exists?(note.id)).to be false
    end

    it 'does not delete another account named in the object' do
      other = create(:actor, :remote)

      expect { post '/inbox', params: delete_activity(other.ap_id), headers: headers }
        .not_to have_enqueued_job(DeleteRemoteActorJob)
    end
  end

  describe 'POST /users/:username/inbox' do
    let(:local_actor) { create(:actor) }

    it 'schedules deleting the account when it deletes itself' do
      expect do
        post "/users/#{local_actor.username}/inbox", params: delete_activity(remote.ap_id), headers: headers
      end.to have_enqueued_job(DeleteRemoteActorJob).with(remote.id)

      expect(response).to have_http_status(:accepted)
    end
  end
end
