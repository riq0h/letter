# frozen_string_literal: true

require 'rails_helper'

# 転送されたアクティビティは本文を使わない(なりすまし対策)
RSpec.describe ForwardedActivityHandling, type: :controller do
  include ActiveJob::TestHelper

  controller(ApplicationController) do
    include ForwardedActivityHandling # rubocop:disable RSpec/DescribedClass

    def test_action
      @forwarded_by = 'https://forwarder.example/users/bob'
      @activity = JSON.parse(request.raw_post)
      handle_forwarded_activity
    end
  end

  before { routes.draw { post 'test_action' => 'anonymous#test_action' } }

  let(:victim_uri) { 'https://victim.example/users/v' }

  it 'refetches a forwarded Create from its origin instead of trusting the payload' do
    body = { 'type' => 'Create', 'actor' => victim_uri,
             'object' => { 'id' => 'https://victim.example/notes/1', 'type' => 'Note', 'content' => 'FORGED' } }

    expect { post :test_action, body: body.to_json }
      .to have_enqueued_job(FetchForwardedObjectJob).with('https://victim.example/notes/1', victim_uri, nil)
    expect(response).to have_http_status(:accepted)
    expect(ActivityPubObject.exists?(ap_id: 'https://victim.example/notes/1')).to be false
  end

  it 'ignores a boost forwarded by someone other than a subscribed relay' do
    body = { 'type' => 'Announce', 'actor' => victim_uri, 'object' => 'https://victim.example/notes/1' }

    expect { post :test_action, body: body.to_json }.not_to have_enqueued_job
    expect(response).to have_http_status(:accepted)
  end

  it 'ignores a forwarded Delete of a post this server does not have' do
    body = { 'type' => 'Delete', 'actor' => victim_uri, 'object' => 'https://victim.example/notes/1' }

    expect { post :test_action, body: body.to_json }.not_to have_enqueued_job
    expect(response).to have_http_status(:accepted)
  end

  %w[Delete Update].each do |type|
    it "checks a forwarded #{type} of a post this server has at its origin, instead of applying it" do
      victim = create(:actor, :remote, domain: 'victim.example', ap_id: victim_uri)
      status = create(:activity_pub_object, :remote, actor: victim, ap_id: 'https://victim.example/notes/1', content: '<p>original</p>')
      body = { 'type' => type, 'actor' => victim_uri,
               'object' => { 'id' => status.ap_id, 'type' => 'Note', 'content' => 'FORGED' } }

      expect { post :test_action, body: body.to_json }
        .to have_enqueued_job(ApplyForwardedChangeJob).with(type, status.ap_id, victim_uri)
      expect(status.reload.content).to eq('<p>original</p>')
    end
  end

  it 'ignores other forwarded activities (e.g. Like)' do
    body = { 'type' => 'Like', 'actor' => victim_uri, 'object' => 'https://victim.example/notes/1' }

    expect { post :test_action, body: body.to_json }.not_to have_enqueued_job
    expect(response).to have_http_status(:accepted)
  end
end
