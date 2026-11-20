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

  describe 'tracking delivery failures per server' do
    def respond(inbox, result)
      allow(sender).to receive(:send_activity).with(hash_including(target_inbox: inbox)).and_return(result)
    end

    # 削除済みアカウントの宛先が410を返しても、同じサーバのほかの人には配送を続ける
    it 'neither stops delivery to the server nor removes follows when an inbox answers 410' do
      follower = create(:actor, :remote)
      create(:follow, :accepted, actor: follower, target_actor: actor)
      gone_inbox = 'https://remote.example.com/users/deleted/inbox'
      respond(gone_inbox, { success: false, code: 410, error: '410 Gone' })

      described_class.new.perform(activity.id, [gone_inbox])

      expect(UnavailableServer.exists?(domain: 'remote.example.com')).to be false
      expect(Follow.where(actor: follower, target_actor: actor)).to exist
    end

    it 'records a failure when the server does not respond' do
      respond(inboxes.first, { success: false, error: 'Timeout: execution expired' })

      described_class.new.perform(activity.id, inboxes)

      expect(UnavailableServer.find_by(domain: 'server1.example')).to have_attributes(error_count: 1, reason: 'timeout')
    end

    it 'skips a server whose failures have lasted for the failure period' do
      create(:unavailable_server, domain: 'server1.example', first_error_at: 15.days.ago, last_error_at: 1.hour.ago)

      described_class.new.perform(activity.id, inboxes)

      expect(sender).not_to have_received(:send_activity).with(hash_including(target_inbox: inboxes.first))
      expect(sender).to have_received(:send_activity).exactly(inboxes.size - 1).times
    end

    it 'keeps delivering to a server with recent failures and clears them on success' do
      create(:unavailable_server, domain: 'server1.example', first_error_at: 2.days.ago, last_error_at: 1.hour.ago)

      described_class.new.perform(activity.id, inboxes)

      expect(sender).to have_received(:send_activity).with(hash_including(target_inbox: inboxes.first))
      expect(UnavailableServer.exists?(domain: 'server1.example')).to be false
    end
  end
end
