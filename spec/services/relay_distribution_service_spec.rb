# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RelayDistributionService do
  let(:service) { described_class.new }
  let(:actor) { create(:actor) }
  let(:activity_sender) { instance_double(ActivitySender) }

  before do
    allow(ActivitySender).to receive(:new).and_return(activity_sender)
    allow(activity_sender).to receive(:send_activity).and_return({ success: true })
  end

  describe '#distribute_to_relays' do
    context 'with visibility filtering' do
      before { create(:relay, :accepted) }

      it 'distributes public notes' do
        object = create(:activity_pub_object, actor: actor, local: true, visibility: 'public', object_type: 'Note')

        service.distribute_to_relays(object)

        expect(activity_sender).to have_received(:send_activity)
      end

      it 'does not distribute unlisted notes' do
        object = create(:activity_pub_object, actor: actor, local: true, visibility: 'unlisted', object_type: 'Note')

        service.distribute_to_relays(object)

        expect(activity_sender).not_to have_received(:send_activity)
      end

      it 'does not distribute private notes' do
        object = create(:activity_pub_object, actor: actor, local: true, visibility: 'private', object_type: 'Note')

        service.distribute_to_relays(object)

        expect(activity_sender).not_to have_received(:send_activity)
      end

      it 'does not distribute direct notes' do
        object = create(:activity_pub_object, actor: actor, local: true, visibility: 'direct', object_type: 'Note')

        service.distribute_to_relays(object)

        expect(activity_sender).not_to have_received(:send_activity)
      end

      it 'does not distribute remote objects' do
        remote_actor = create(:actor, :remote)
        object = create(:activity_pub_object, actor: remote_actor, local: false, visibility: 'public',
                                              object_type: 'Note', ap_id: 'https://remote.example.com/notes/1')

        service.distribute_to_relays(object)

        expect(activity_sender).not_to have_received(:send_activity)
      end
    end

    context 'with delivery_attempts tracking' do
      let!(:relay) { create(:relay, :accepted, delivery_attempts: 2) }
      let(:object) { create(:activity_pub_object, actor: actor, local: true, visibility: 'public', object_type: 'Note') }

      it 'resets delivery_attempts on successful delivery' do
        allow(activity_sender).to receive(:send_activity).and_return({ success: true })

        service.distribute_to_relays(object)

        expect(relay.reload.delivery_attempts).to eq(0)
      end

      it 'increments delivery_attempts on failure' do
        relay.update_column(:delivery_attempts, 0)
        allow(activity_sender).to receive(:send_activity).and_return({ success: false })

        service.distribute_to_relays(object)

        expect(relay.reload.delivery_attempts).to eq(1)
      end

      it 'disables relay after 3 consecutive failures' do
        allow(activity_sender).to receive(:send_activity).and_return({ success: false })

        service.distribute_to_relays(object)

        relay.reload
        expect(relay.state).to eq('idle')
        expect(relay.last_error).to include('Too many delivery failures')
      end
    end

    context 'when no enabled relays exist' do
      it 'does not attempt delivery' do
        object = create(:activity_pub_object, actor: actor, local: true, visibility: 'public', object_type: 'Note')

        service.distribute_to_relays(object)

        expect(activity_sender).not_to have_received(:send_activity)
      end
    end
  end
end
