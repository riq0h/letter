# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendActivityJob do
  let(:actor) { create(:actor, local: true) }
  let(:activity) { create(:activity, actor: actor) }
  let(:sender) { instance_double(ActivitySender) }
  let(:inboxes) { (1..20).map { |i| "https://server#{i}.example/inbox" } }

  before do
    allow(ActivitySender).to receive(:new).and_return(sender)
    allow(sender).to receive(:send_activity).and_return({ success: true, code: 202 })
  end

  it 'delivers to every inbox exactly once, building the activity only once' do
    job = described_class.new
    allow(job).to receive(:build_activity_data).and_call_original

    job.perform(activity.id, inboxes + [inboxes.first])

    expect(job).to have_received(:build_activity_data).once
    inboxes.each do |inbox|
      expect(sender).to have_received(:send_activity).with(hash_including(target_inbox: inbox)).once
    end
  end

  it 'keeps delivering to the rest when one inbox raises' do
    allow(sender).to receive(:send_activity).with(hash_including(target_inbox: inboxes.first)).and_raise('boom')

    described_class.new.perform(activity.id, inboxes)

    expect(sender).to have_received(:send_activity).exactly(inboxes.size).times
    expect(activity.reload.delivered).to be true
  end
end
