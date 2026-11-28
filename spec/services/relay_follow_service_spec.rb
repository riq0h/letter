# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RelayFollowService do
  let(:sender) { instance_double(ActivitySender) }
  let(:sent) { [] }
  let(:delivery_result) { { success: true, code: 202 } }
  let(:relay) { create(:relay, :rejected) }

  before do
    create(:actor)
    allow(ActivitySender).to receive(:new).and_return(sender)
    allow(sender).to receive(:send_activity) { |**args| sent << args and delivery_result }
    allow_any_instance_of(described_class).to receive(:fetch_activitypub_object)
      .and_return({ 'id' => relay.actor_uri, 'type' => 'Application' })
  end

  it 'asks a relay that rejected us again' do
    expect(described_class.new.call(relay)).to be(true)

    expect(sent.first[:activity]).to include('type' => 'Follow', 'object' => 'https://www.w3.org/ns/activitystreams#Public')
    expect(relay.reload).to be_pending
    expect(relay.follow_activity_id).to eq(sent.first[:activity]['id'])
  end
end
