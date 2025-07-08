# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublishScheduledStatusOrganizer do
  let(:actor) { create(:actor, local: true) }
  let(:scheduled_status) do
    scheduled_status = ScheduledStatus.new(
      actor: actor,
      params: {
        'status' => 'Hello world!',
        'visibility' => 'public',
        'sensitive' => false
      },
      scheduled_at: 1.hour.ago
    )
    scheduled_status.save!(validate: false)
    scheduled_status
  end

  describe '.call' do
    it 'publishes scheduled status successfully' do
      result = described_class.call(scheduled_status)

      expect(result).to be_success
      expect(result.status).to be_a(ActivityPubObject)
      expect(result.status.content).to eq('Hello world!')
      expect(result.status.visibility).to eq('public')
      expect(result.status.local).to be(true)
    end

    it 'deletes scheduled status after publishing' do
      # scheduled_statusを事前に作成
      status = scheduled_status

      expect { described_class.call(status) }
        .to change(ScheduledStatus, :count).by(-1)
    end

    it 'creates status with correct attributes' do
      result = described_class.call(scheduled_status)

      status = result.status
      expect(status.actor).to eq(actor)
      expect(status.object_type).to eq('Note')
      expect(status.published_at).to be_within(1.second).of(Time.current)
      expect(status.ap_id).to include(actor.username)
    end
  end

  describe '#call' do
    subject(:organizer) { described_class.new(scheduled_status) }

    context 'with media attachments' do
      let(:media_attachment) { create(:media_attachment, actor: actor) }
      let(:scheduled_status_with_media) do
        create(:scheduled_status,
               actor: actor,
               params: { 'status' => 'With media' },
               media_attachment_ids: [media_attachment.id])
      end

      it 'attaches media to created status' do
        organizer = described_class.new(scheduled_status_with_media)
        result = organizer.call

        expect(result).to be_success
        media_attachment.reload
        expect(media_attachment.object_id).to eq(result.status.id)
      end
    end

    context 'with poll data' do
      let(:scheduled_status_with_poll) do
        create(:scheduled_status,
               actor: actor,
               params: {
                 'status' => 'Poll question?',
                 'poll' => {
                   'options' => ['Option 1', 'Option 2'],
                   'expires_in' => 3600,
                   'multiple' => false
                 }
               })
      end

      it 'creates poll for status' do
        allow(PollCreationService).to receive(:create_for_status)

        organizer = described_class.new(scheduled_status_with_poll)
        result = organizer.call

        expect(result).to be_success
        expect(PollCreationService).to have_received(:create_for_status)
          .with(result.status, hash_including(
                                 options: ['Option 1', 'Option 2'],
                                 expires_in: 3600,
                                 multiple: false
                               ))
      end
    end

    context 'with reply parameters' do
      let(:parent_status) { create(:activity_pub_object, actor: actor) }
      let(:scheduled_reply) do
        create(:scheduled_status,
               actor: actor,
               params: {
                 'status' => 'This is a reply',
                 'in_reply_to_id' => parent_status.ap_id
               })
      end

      it 'creates reply status correctly' do
        organizer = described_class.new(scheduled_reply)
        result = organizer.call

        expect(result).to be_success
        expect(result.status.in_reply_to_ap_id).to eq(parent_status.ap_id)
      end
    end

    context 'with sensitive content' do
      let(:sensitive_scheduled_status) do
        create(:scheduled_status,
               actor: actor,
               params: {
                 'status' => 'Sensitive content',
                 'sensitive' => true,
                 'spoiler_text' => 'Content warning'
               })
      end

      it 'creates status with sensitivity settings' do
        organizer = described_class.new(sensitive_scheduled_status)
        result = organizer.call

        expect(result).to be_success
        expect(result.status.sensitive).to be(true)
        expect(result.status.summary).to eq('Content warning')
      end
    end

    it 'handles errors gracefully' do
      allow(actor.objects).to receive(:create!).and_raise(StandardError, 'Database error')

      result = organizer.call

      expect(result).to be_failure
      expect(result.error).to eq('Database error')
    end

    it 'rolls back transaction on error' do
      # scheduled_statusを事前に作成してから、エラーを発生させる
      status = scheduled_status
      organizer = described_class.new(status)
      allow(status.actor.objects).to receive(:create!).and_raise(StandardError, 'Database error')

      expect { organizer.call }.not_to(change(ScheduledStatus, :count))
    end
  end

  describe 'Result class' do
    describe '#success?' do
      it 'returns true for successful result' do
        result = described_class::Result.new(success: true)
        expect(result).to be_success
      end

      it 'returns false for failed result' do
        result = described_class::Result.new(success: false)
        expect(result).not_to be_success
      end
    end

    describe '#failure?' do
      it 'returns false for successful result' do
        result = described_class::Result.new(success: true)
        expect(result).not_to be_failure
      end

      it 'returns true for failed result' do
        result = described_class::Result.new(success: false)
        expect(result).to be_failure
      end
    end

    describe 'immutability' do
      it 'is immutable' do
        result = described_class::Result.new(success: true)
        expect(result).to be_frozen
      end
    end
  end

  describe 'parameter handling' do
    context 'with default visibility' do
      let(:scheduled_status_no_visibility) do
        create(:scheduled_status,
               actor: actor,
               params: { 'status' => 'Default visibility' })
      end

      it 'defaults to public visibility' do
        result = described_class.call(scheduled_status_no_visibility)

        expect(result).to be_success
        expect(result.status.visibility).to eq('public')
      end
    end

    context 'with various visibility levels' do
      %w[public unlisted private direct].each do |visibility|
        it "handles #{visibility} visibility correctly" do
          scheduled_status = create(:scheduled_status,
                                    actor: actor,
                                    params: {
                                      'status' => "#{visibility.capitalize} post",
                                      'visibility' => visibility
                                    })

          result = described_class.call(scheduled_status)

          expect(result).to be_success
          expect(result.status.visibility).to eq(visibility)
        end
      end
    end
  end
end
