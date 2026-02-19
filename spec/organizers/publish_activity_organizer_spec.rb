# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublishActivityOrganizer do
  let(:actor) { create(:actor, local: true) }
  let(:remote_actor) { create(:actor, :remote) }
  let(:follower) { create(:actor, :remote) }

  before do
    # フォロワー関係を設定
    create(:follow, actor: follower, target_actor: actor, accepted: true)

    # トランザクションテストではafter_commitが発火しないため、
    # enqueue_send_activityをバイパスして直接perform_laterを呼ぶ
    allow_any_instance_of(described_class).to receive(:enqueue_send_activity) do |_obj, activity, inbox_urls|
      SendActivityJob.perform_later(activity.id, inbox_urls) if inbox_urls.present?
    end
    allow_any_instance_of(ActivityPubObject).to receive(:enqueue_send_activity) do |_obj, activity, inbox_urls|
      SendActivityJob.perform_later(activity.id, inbox_urls) if inbox_urls.present?
    end
  end

  describe '.call' do
    context 'with Create activity' do
      it 'creates activity and queues delivery' do
        result = described_class.call(
          actor,
          activity_type: 'Create',
          content: 'Hello world!',
          visibility: 'public'
        )

        expect(result).to be_success
        expect(result.activity).to be_a(Activity)
        expect(result.activity.activity_type).to eq('Create')
        expect(result.activity.object).to be_a(ActivityPubObject)
        # after_createでprocess_text_contentが実行され<p>タグで囲まれる
        expect(result.activity.object.content).to eq('<p>Hello world!</p>')
      end

      it 'delivers to followers' do
        # Create activityはActivityPubObjectが自動配信するため、Organizer側では配信しない
        # しかしActivityPubObjectのコールバックにより配信される
        expect(SendActivityJob).to receive(:perform_later).once

        result = described_class.call(
          actor,
          activity_type: 'Create',
          content: 'Test post'
        )

        expect(result).to be_success
      end
    end

    context 'with Follow activity' do
      it 'creates activity and delivers to target' do
        expect(SendActivityJob).to receive(:perform_later)

        result = described_class.call(
          actor,
          activity_type: 'Follow',
          target_ap_id: remote_actor.ap_id
        )

        expect(result).to be_success
        expect(result.activity.activity_type).to eq('Follow')
        expect(result.activity.target_ap_id).to eq(remote_actor.ap_id)
      end

      it 'fails without target_ap_id' do
        result = described_class.call(
          actor,
          activity_type: 'Follow'
        )

        expect(result).to be_failure
        expect(result.error).to include('Target AP ID required')
      end
    end

    context 'with Announce activity' do
      let(:object) { create(:activity_pub_object) }

      it 'creates announce activity' do
        # Announce activityはフォロワー配信（1回）+ ターゲット配信（1回）
        allow_any_instance_of(described_class).to receive(:find_target_actor).and_return(remote_actor)

        expect(SendActivityJob).to receive(:perform_later).twice

        result = described_class.call(
          actor,
          activity_type: 'Announce',
          target_ap_id: object.ap_id
        )

        expect(result).to be_success
        expect(result.activity.activity_type).to eq('Announce')
      end
    end

    context 'with Like activity' do
      let(:object) { create(:activity_pub_object) }

      it 'creates like activity' do
        # Like activityはフォロワーへの配信なし、ターゲットのみ
        # ただし、target_actorが見つからない場合は配信されない
        allow_any_instance_of(described_class).to receive(:find_target_actor).and_return(remote_actor)

        expect(SendActivityJob).to receive(:perform_later).once

        result = described_class.call(
          actor,
          activity_type: 'Like',
          target_ap_id: object.ap_id
        )

        expect(result).to be_success
        expect(result.activity.activity_type).to eq('Like')
      end
    end

    context 'with Undo activity' do
      let(:original_activity) { create(:activity, actor: actor) }

      it 'creates undo activity' do
        expect(SendActivityJob).to receive(:perform_later).twice

        result = described_class.call(
          actor,
          activity_type: 'Undo',
          target_ap_id: original_activity.ap_id
        )

        expect(result).to be_success
        expect(result.activity.activity_type).to eq('Undo')
      end
    end

    context 'with Delete activity' do
      let(:object) { create(:activity_pub_object, actor: actor) }

      it 'creates delete activity' do
        expect(SendActivityJob).to receive(:perform_later).twice

        result = described_class.call(
          actor,
          activity_type: 'Delete',
          target_ap_id: object.ap_id
        )

        expect(result).to be_success
        expect(result.activity.activity_type).to eq('Delete')
      end
    end

    context 'with unsupported activity type' do
      it 'returns failure' do
        result = described_class.call(
          actor,
          activity_type: 'Unknown'
        )

        expect(result).to be_failure
        expect(result.error).to include('Unsupported activity type')
      end
    end
  end

  describe '#call' do
    subject(:organizer) { described_class.new(actor, activity_type: 'Create', content: 'Test') }

    it 'handles errors gracefully' do
      allow(Activity).to receive(:create!).and_raise(StandardError, 'Database error')

      result = organizer.call

      expect(result).to be_failure
      expect(result.error).to eq('Database error')
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

  describe 'inbox URL optimization' do
    let(:shared_inbox_url) { 'https://shared.example.com/inbox' }
    let(:individual_inbox_url) { 'https://shared.example.com/users/user1/inbox' }
    let(:other_inbox_url) { 'https://other.example.com/users/user2/inbox' }

    before do
      # 複数のフォロワーを設定
      # shared_inbox_urlメソッドはraw_dataから読むため、raw_dataにsharedInboxを設定
      follower1 = create(:actor, :remote,
                         inbox_url: individual_inbox_url,
                         raw_data: { 'endpoints' => { 'sharedInbox' => shared_inbox_url } }.to_json)
      follower2 = create(:actor, :remote,
                         inbox_url: other_inbox_url)

      create(:follow, actor: follower1, target_actor: actor, accepted: true)
      create(:follow, actor: follower2, target_actor: actor, accepted: true)
    end

    it 'prioritizes shared inbox over individual inboxes' do
      organizer = described_class.new(actor, activity_type: 'Create', content: 'Test')

      # collect_follower_inboxesを直接テスト
      follower_inboxes = organizer.send(:collect_follower_inboxes)
      expect(follower_inboxes).to include(shared_inbox_url)
      expect(follower_inboxes).to include(other_inbox_url)
      # shared_inbox_urlがあるドメインのindividual_inboxは除外される
      expect(follower_inboxes).not_to include(individual_inbox_url)
    end
  end
end
