# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Streaming::Hub do
  let(:hub) { described_class.new }
  let(:user) { create(:actor) }
  let(:session) { instance_double(Streaming::Session, user: user, timelines?: false) }

  before do
    allow(hub).to receive(:ensure_thread)
    allow(session).to receive(:deliver)
    allow(Streaming::Listeners).to receive(:mark)
  end

  def record_event(target_id)
    StreamingEvent.create!(kind: 'delete', target_id: target_id, created_at: Time.current)
  end

  it 'delivers only what happened after the first connection' do
    record_event('1')
    hub.register(session)
    newer = record_event('2')

    hub.dispatch_pending

    expect(session).to have_received(:deliver).once.with(newer, kind_of(Streaming::Renderer))
  end

  it 'delivers each event once' do
    hub.register(session)
    record_event('1')

    2.times { hub.dispatch_pending }

    expect(session).to have_received(:deliver).once
  end

  it 'stops delivering to a closed connection' do
    hub.register(session)
    hub.unregister(session)
    record_event('1')

    hub.dispatch_pending

    expect(session).not_to have_received(:deliver)
  end

  it 'keeps delivering to the other connections when one fails' do
    other = instance_double(Streaming::Session, user: user, timelines?: false)
    allow(other).to receive(:deliver)
    allow(session).to receive(:deliver).and_raise(IOError)
    [session, other].each { |s| hub.register(s) }
    record_event('1')

    hub.dispatch_pending

    expect(other).to have_received(:deliver).once
  end

  it 'marks the connected users as listening' do
    hub.register(session)

    expect(Streaming::Listeners).to have_received(:mark).with(user_ids: [user.id], timelines: false)
  end
end
