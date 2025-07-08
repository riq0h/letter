# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StreamingDelivery do
  let(:actor) { create(:actor, local: true) }
  let(:remote_actor) { create(:actor, :remote) }
  let(:status) { create(:activity_pub_object, actor: actor, visibility: 'public', object_type: 'Note') }
  let(:notification) { create(:notification, account: actor, from_account: remote_actor) }
  let(:tag) { create(:tag, name: 'test') }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '.deliver_status_update' do
    context 'when status is a public Note' do
      it 'broadcasts to public timeline' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'timeline:public',
          hash_including(event: 'update')
        )

        described_class.deliver_status_update(status)
      end

      it 'broadcasts to local timeline when status is local' do
        allow(status).to receive(:local?).and_return(true)

        expect(ActionCable.server).to receive(:broadcast).with(
          'timeline:public:local',
          hash_including(event: 'update')
        )

        described_class.deliver_status_update(status)
      end

      it 'broadcasts to hashtag streams when status has hashtags' do
        allow(status).to receive_messages(tags: [tag], local?: true)

        expect(ActionCable.server).to receive(:broadcast).with(
          "hashtag:#{tag.name.downcase}",
          hash_including(event: 'update')
        )

        expect(ActionCable.server).to receive(:broadcast).with(
          "hashtag:#{tag.name.downcase}:local",
          hash_including(event: 'update')
        )

        described_class.deliver_status_update(status)
      end

      it 'broadcasts to follower home timelines when status has followers' do
        follower = create(:actor, local: true)
        create(:follow, actor: follower, target_actor: actor)

        # フォロワーリレーションのモックをより明示的に作成
        local_followers = double('local_followers')
        allow(local_followers).to receive(:pluck).with(:id).and_return([follower.id])

        followers_relation = double('followers_relation')
        allow(followers_relation).to receive(:local).and_return(local_followers)

        allow(status.actor).to receive(:followers).and_return(followers_relation)

        expect(ActionCable.server).to receive(:broadcast).with(
          "timeline:home:#{follower.id}",
          hash_including(event: 'update')
        )

        described_class.deliver_status_update(status)
      end
    end

    context 'when status is not a Note' do
      before { status.object_type = 'Article' }

      it 'does not broadcast anything' do
        expect(ActionCable.server).not_to receive(:broadcast)

        described_class.deliver_status_update(status)
      end
    end

    context 'when status is private' do
      before { status.visibility = 'private' }

      it 'does not broadcast to public timeline' do
        expect(ActionCable.server).not_to receive(:broadcast).with(
          'timeline:public',
          anything
        )

        described_class.deliver_status_update(status)
      end
    end
  end

  describe '.deliver_status_delete' do
    let(:status_id) { 123 }

    it 'broadcasts delete event to public timelines' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'timeline:public',
        { event: 'delete', payload: '123' }
      )

      expect(ActionCable.server).to receive(:broadcast).with(
        'timeline:public:local',
        { event: 'delete', payload: '123' }
      )

      described_class.deliver_status_delete(status_id)
    end
  end

  describe '.deliver_notification' do
    it 'broadcasts notification to user channel' do
      expect(ActionCable.server).to receive(:broadcast).with(
        "notifications:#{notification.account_id}",
        hash_including(
          event: 'notification',
          payload: hash_including(
            id: notification.id.to_s,
            type: notification.notification_type
          )
        )
      )

      described_class.deliver_notification(notification)
    end
  end

  describe 'serialization methods' do
    let(:instance) { described_class.new }

    describe '#serialize_status' do
      it 'serializes status with all required fields' do
        result = instance.send(:serialize_status, status)

        expect(result).to include(
          id: status.id.to_s,
          content: status.content,
          visibility: status.visibility,
          account: hash_including(
            id: status.actor.id.to_s,
            username: status.actor.username
          )
        )
      end
    end

    describe '#serialize_account' do
      it 'serializes account with all required fields' do
        result = instance.send(:serialize_account, actor)

        expect(result).to include(
          id: actor.id.to_s,
          username: actor.username,
          display_name: actor.display_name,
          locked: actor.locked?,
          bot: actor.bot?
        )
      end
    end

    describe '#serialize_notification' do
      it 'serializes notification with all required fields' do
        result = instance.send(:serialize_notification, notification)

        expect(result).to include(
          id: notification.id.to_s,
          type: notification.notification_type,
          account: hash_including(
            id: notification.from_account.id.to_s
          )
        )
      end
    end

    describe '#sanitize_content' do
      it 'removes unsafe HTML tags' do
        html = '<script>alert("xss")</script><p>Safe content</p>'

        result = instance.send(:sanitize_content, html)

        expect(result).to eq('alert("xss")<p>Safe content</p>')
      end

      it 'handles blank content' do
        expect(instance.send(:sanitize_content, '')).to eq('')
        expect(instance.send(:sanitize_content, nil)).to eq('')
      end
    end
  end

  describe 'private broadcast methods' do
    let(:instance) { described_class.new }
    let(:serialized_status) { { id: '1', content: 'test' } }

    describe '#broadcast_to_public_timeline' do
      it 'broadcasts to public timeline channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'timeline:public',
          { event: 'update', payload: serialized_status }
        )

        instance.send(:broadcast_to_public_timeline, serialized_status)
      end
    end

    describe '#broadcast_to_local_timeline' do
      it 'broadcasts to local timeline channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'timeline:public:local',
          { event: 'update', payload: serialized_status }
        )

        instance.send(:broadcast_to_local_timeline, serialized_status)
      end
    end

    describe '#broadcast_to_home_timeline' do
      it 'broadcasts to specific home timeline channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'timeline:home:123',
          { event: 'update', payload: serialized_status }
        )

        instance.send(:broadcast_to_home_timeline, 123, serialized_status)
      end
    end

    describe '#broadcast_to_list_timeline' do
      it 'broadcasts to specific list timeline channel' do
        expect(ActionCable.server).to receive(:broadcast).with(
          'list:456',
          { event: 'update', payload: serialized_status }
        )

        instance.send(:broadcast_to_list_timeline, 456, serialized_status)
      end
    end
  end

  describe 'event building methods' do
    let(:instance) { described_class.new }

    describe '#build_delete_event' do
      it 'builds delete event structure' do
        result = instance.send(:build_delete_event, 123)

        expect(result).to eq({
                               event: 'delete',
                               payload: '123'
                             })
      end
    end

    describe '#build_hashtag_event' do
      it 'builds hashtag event structure' do
        payload = { id: '1', content: 'test' }
        result = instance.send(:build_hashtag_event, payload)

        expect(result).to eq({
                               event: 'update',
                               payload: payload
                             })
      end
    end
  end
end
