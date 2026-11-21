# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Create activities that refer to the post only by its URL', type: :request do
  let(:remote) { create(:actor, :remote) }
  let(:local_actor) { create(:actor) }
  let(:verifier) { instance_double(HttpSignatureVerifier, verify!: true) }
  let(:headers) do
    { 'Content-Type' => 'application/activity+json',
      'Signature' => %(keyId="#{remote.ap_id}#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="x") }
  end

  def activity(type, object)
    { '@context' => 'https://www.w3.org/ns/activitystreams', 'id' => "#{remote.ap_id}/activities/1",
      'type' => type, 'actor' => remote.ap_id, 'object' => object }.to_json
  end

  before { allow(HttpSignatureVerifier).to receive(:new).and_return(verifier) }

  # fedibirdの限定公開の投稿などは、本文を含まず投稿のURLだけで届く
  it 'fetches a post that a Create refers to only by its URL' do
    note_uri = "#{remote.ap_id}/statuses/2"

    %W[/users/#{local_actor.username}/inbox /inbox].each do |path|
      expect { post path, params: activity('Create', note_uri), headers: headers }
        .to have_enqueued_job(FetchForwardedObjectJob).with(note_uri, remote.ap_id)
      expect(response).to have_http_status(:accepted)
    end
  end
end
