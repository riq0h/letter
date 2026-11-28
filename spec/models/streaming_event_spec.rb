# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StreamingEvent do
  let(:author) { create(:actor, :remote) }

  before { allow(Streaming::Listeners).to receive_messages(listening?: true, timelines_listening?: true) }

  def recorded(kind)
    described_class.where(kind: kind).pluck(:target_id, :recipient_id, :public_visibility)
  end

  it 'records nothing while nobody is connected' do
    allow(Streaming::Listeners).to receive_messages(listening?: false, timelines_listening?: false)

    status = create(:activity_pub_object, :remote, actor: author)
    create(:notification, activity_id: status.id.to_s)
    status.destroy!

    expect(described_class.count).to eq(0)
  end

  it 'records an event only once the transaction has been committed' do
    status = create(:activity_pub_object, :remote, actor: author)
    described_class.delete_all

    ActiveRecord::Base.transaction do
      described_class.publish_status_update(status)
      expect(described_class.count).to eq(0)
    end

    expect(recorded('status.update')).to eq([[status.id.to_s, nil, false]])
  end

  it 'records nothing for a rolled back transaction' do
    status = create(:activity_pub_object, :remote, actor: author)
    described_class.delete_all

    ActiveRecord::Base.transaction do
      described_class.publish_status_update(status)
      raise ActiveRecord::Rollback
    end

    expect(described_class.count).to eq(0)
  end

  describe 'what gets recorded' do
    it 'records a new post for the timelines, but not a direct message' do
      status = create(:activity_pub_object, :remote, actor: author)
      create(:activity_pub_object, :remote, :direct, actor: author)

      expect(recorded('status')).to eq([[status.id.to_s, nil, false]])
    end

    it 'records nothing for the timelines while nobody follows a timeline stream' do
      allow(Streaming::Listeners).to receive(:timelines_listening?).and_return(false)

      create(:activity_pub_object, :remote, actor: author)

      expect(recorded('status')).to be_empty
    end

    it 'records an edit made on this server once it is complete' do
      status = create(:activity_pub_object, actor: create(:actor))

      status.perform_edit!(content: 'edited')

      expect(recorded('status.update')).to eq([[status.id.to_s, nil, false]])
    end

    it 'records an edit received from another server after its attachments are replaced' do
      status = create(:activity_pub_object, :remote, actor: author)
      handler = Class.new do
        include ActivityPubObjectHandlers

        def initialize(sender) = @sender = sender
        def run(object_data) = update_object_content(object_data)
      end
      allow(described_class).to receive(:publish_status_update) do |object|
        expect(object.media_attachments.reload.size).to eq(1)
      end

      handler.new(author).run('id' => status.ap_id, 'type' => 'Note', 'content' => 'edited',
                              'updated' => Time.current.iso8601,
                              'attachment' => [{ 'type' => 'Document', 'mediaType' => 'image/png',
                                                 'url' => 'https://remote.example.com/files/a.png' }])

      expect(described_class).to have_received(:publish_status_update).once
    end

    it 'does not record a remote update that is not an edit' do
      status = create(:activity_pub_object, :remote, actor: author)
      allow(described_class).to receive(:publish_status_update)
      handler = Class.new do
        include ActivityPubObjectHandlers

        def initialize(sender) = @sender = sender
        def run(object_data) = update_object_content(object_data)
      end

      handler.new(author).run('id' => status.ap_id, 'type' => 'Note', 'content' => status.content)

      expect(described_class).not_to have_received(:publish_status_update)
    end

    it 'records a deleted post with whether it was public' do
      public_status = create(:activity_pub_object, :remote, actor: author)
      private_status = create(:activity_pub_object, :remote, :private, actor: author)

      public_status.destroy!
      private_status.destroy!

      expect(recorded('delete')).to contain_exactly([public_status.id.to_s, nil, true], [private_status.id.to_s, nil, false])
    end

    it 'records a withdrawn boost by the id it has on timelines' do
      reblog = create(:reblog, actor: author)
      timeline_id = reblog.timeline_id

      reblog.destroy!

      expect(recorded('delete')).to eq([[timeline_id, nil, false]])
    end

    it 'records a notification for its recipient' do
      notification = create(:notification, from_account: author)

      expect(recorded('notification')).to eq([[notification.id.to_s, notification.account_id, false]])
    end

    it 'records a direct message conversation for each participant on this server' do
      user = create(:actor)
      conversation = Conversation.find_or_create_for_actors([user, author])

      conversation.update_last_status!(create(:activity_pub_object, :remote, :direct, actor: author))

      expect(recorded('conversation')).to eq([[conversation.id.to_s, user.id, false]])
    end

    it 'records a post added to the home timeline once' do
      user = Actor.find_by(local: true) || create(:actor)
      create(:follow, actor: user, target_actor: author, accepted: true)
      status = create(:activity_pub_object, :remote, actor: author)

      2.times { HomeFeedManager.add_status(status) }

      expect(recorded('home')).to eq([[status.id.to_s, user.id, false]])
    end
  end

  it 'removes events old enough to have been delivered' do
    old = described_class.create!(kind: 'delete', target_id: '1', created_at: 11.minutes.ago)
    recent = described_class.create!(kind: 'delete', target_id: '2', created_at: 1.minute.ago)

    described_class.trim

    expect(described_class.pluck(:id)).to eq([recent.id])
    expect(described_class.exists?(old.id)).to be(false)
  end
end
