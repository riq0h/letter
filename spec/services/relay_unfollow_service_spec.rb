# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RelayUnfollowService do
  let!(:local_actor) { create(:actor) }
  let(:sender) { instance_double(ActivitySender) }
  let(:sent) { [] }
  let(:delivery_result) { { success: true, code: 202 } }
  let(:relay) { create(:relay, :accepted) }

  before do
    allow(ActivitySender).to receive(:new).and_return(sender)
    allow(sender).to receive(:send_activity) { |**args| sent << args and delivery_result }
  end

  it 'sends an Undo of the original Follow and stops the subscription' do
    follow_id = relay.follow_activity_id

    expect(described_class.new.call(relay)).to be(true)

    expect(sent.first[:target_inbox]).to eq(relay.inbox_url)
    expect(sent.first[:activity]).to include('type' => 'Undo', 'actor' => local_actor.ap_id)
    expect(sent.first[:activity]['object']).to include('id' => follow_id, 'type' => 'Follow')
    expect(relay.reload).to be_idle
    expect(relay.follow_activity_id).to be_nil
  end

  it 'stops the subscription even when the relay cannot be reached, keeping the error' do
    allow(sender).to receive(:send_activity).and_return({ success: false, error: 'Timeout' })

    described_class.new.call(relay)

    expect(relay.reload).to be_idle
    expect(relay.last_error).to include('Timeout')
  end

  it 'withdraws a Follow still waiting for an answer' do
    pending_relay = create(:relay, :pending)

    described_class.new.call(pending_relay)

    expect(sent.first[:activity]).to include('type' => 'Undo')
    expect(pending_relay.reload).to be_idle
  end
end
