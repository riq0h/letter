# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusActionOrganizer do
  let(:actor) { create(:actor, local: true) }
  let(:status_actor) { create(:actor, :remote) }
  let(:status) { create(:activity_pub_object, actor: status_actor) }

  describe '.call' do
    context 'with like action' do
      it 'creates like activity successfully' do
        result = described_class.call(actor, action_type: 'like', status: status)

        expect(result).to be_success
        expect(result.activity).to be_a(Activity)
        expect(result.activity.activity_type).to eq('Like')
        expect(result.activity.actor).to eq(actor)
        expect(result.activity.target_ap_id).to eq(status.ap_id)
      end

      it 'queues activity delivery' do
        expect(SendActivityJob).to receive(:perform_later)

        described_class.call(actor, action_type: 'like', status: status)
      end
    end

    context 'with undo_like action' do
      let!(:like_activity) do
        create(:activity,
               activity_type: 'Like',
               actor: actor,
               target_ap_id: status.ap_id)
      end

      it 'creates undo like activity successfully' do
        result = described_class.call(actor, action_type: 'undo_like', status: status)

        expect(result).to be_success
        expect(result.activity).to be_a(Activity)
        expect(result.activity.activity_type).to eq('Undo')
        expect(result.activity.target_ap_id).to eq(like_activity.ap_id)
      end

      it 'deletes original like activity' do
        expect { described_class.call(actor, action_type: 'undo_like', status: status) }
          .to change { Activity.where(id: like_activity.id).count }.by(-1)
      end

      it 'returns failure when like activity not found' do
        like_activity.destroy

        result = described_class.call(actor, action_type: 'undo_like', status: status)

        expect(result).to be_failure
        expect(result.error).to eq('Like activity not found')
      end
    end

    context 'with announce action' do
      it 'creates announce activity successfully' do
        result = described_class.call(actor, action_type: 'announce', status: status)

        expect(result).to be_success
        expect(result.activity).to be_a(Activity)
        expect(result.activity.activity_type).to eq('Announce')
        expect(result.activity.actor).to eq(actor)
        expect(result.activity.target_ap_id).to eq(status.ap_id)
      end

      it 'queues activity delivery' do
        expect(SendActivityJob).to receive(:perform_later)

        described_class.call(actor, action_type: 'announce', status: status)
      end
    end

    context 'with undo_announce action' do
      let!(:announce_activity) do
        create(:activity,
               activity_type: 'Announce',
               actor: actor,
               target_ap_id: status.ap_id)
      end

      it 'creates undo announce activity successfully' do
        result = described_class.call(actor, action_type: 'undo_announce', status: status)

        expect(result).to be_success
        expect(result.activity).to be_a(Activity)
        expect(result.activity.activity_type).to eq('Undo')
        expect(result.activity.target_ap_id).to eq(announce_activity.ap_id)
      end

      it 'deletes original announce activity' do
        expect { described_class.call(actor, action_type: 'undo_announce', status: status) }
          .to change { Activity.where(id: announce_activity.id).count }.by(-1)
      end

      it 'returns failure when announce activity not found' do
        announce_activity.destroy

        result = described_class.call(actor, action_type: 'undo_announce', status: status)

        expect(result).to be_failure
        expect(result.error).to eq('Announce activity not found')
      end
    end

    context 'with unsupported action type' do
      it 'returns failure' do
        result = described_class.call(actor, action_type: 'unknown', status: status)

        expect(result).to be_failure
        expect(result.error).to include('Unsupported action type')
      end
    end
  end

  describe '#call' do
    subject(:organizer) { described_class.new(actor, action_type: 'like', status: status) }

    it 'handles errors gracefully' do
      # ActivityPubObjectのコールバックを無効化してからActivityモデルにエラーを設定
      allow_any_instance_of(ActivityPubObject).to receive(:create_activity_if_needed)
      allow(Activity).to receive(:create!).and_raise(StandardError, 'Database error')

      result = organizer.call

      expect(result).to be_failure
      expect(result.error).to eq('Database error')
    end

    context 'when status actor has no inbox_url' do
      it 'does not queue delivery job' do
        # inbox_urlを空にする
        status.actor.update_column(:inbox_url, '')

        expect(SendActivityJob).not_to receive(:perform_later)

        described_class.call(actor, action_type: 'like', status: status)
      end
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

  describe 'activity creation' do
    it 'generates unique AP IDs' do
      result1 = described_class.call(actor, action_type: 'like', status: status)
      result2 = described_class.call(actor, action_type: 'announce', status: status)

      expect(result1.activity.ap_id).not_to eq(result2.activity.ap_id)
      expect(result1.activity.ap_id).to include(Rails.application.config.activitypub.base_url)
      expect(result2.activity.ap_id).to include(Rails.application.config.activitypub.base_url)
    end

    it 'sets correct timestamps' do
      result = described_class.call(actor, action_type: 'like', status: status)

      expect(result.activity.published_at).to be_within(1.second).of(Time.current)
    end

    it 'sets local flag correctly' do
      result = described_class.call(actor, action_type: 'like', status: status)

      expect(result.activity.local).to be(true)
    end
  end
end
