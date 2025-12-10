# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PollExpirationNotifyJob, type: :job do
  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:debug)
  end

  describe '#perform' do
    context 'with expired local poll' do
      let(:local_user) { create(:actor, local: true, username: 'testuser') }
      let(:status) { create(:activity_pub_object, actor: local_user, object_type: 'Note') }
      let(:poll) do
        poll = build(:poll, object: status)
        poll.expires_at = 1.hour.ago
        poll.save!(validate: false)
        poll
      end

      before do
        # 手動で投票を作成
        vote = poll.poll_votes.build(actor: local_user, choice: 0)
        vote.save!(validate: false)
        poll.reload
      end

      it 'processes expired poll and creates notification for voter' do
        expect do
          described_class.new.perform(poll.id)
        end.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.notification_type).to eq('poll')
        expect(notification.account).to eq(local_user)
      end

      it 'recalculates vote counts for local poll' do
        expect(poll.poll_votes.count).to eq(1)

        described_class.new.perform(poll.id)
        poll.reload

        expect(poll.votes_count).to eq(1)
        expect(poll.voters_count).to eq(1)
      end

      it 'does not create duplicate notifications' do
        # 初回実行
        described_class.new.perform(poll.id)

        expect do
          # 2回目実行（重複チェック）
          described_class.new.perform(poll.id)
        end.not_to change(Notification, :count)
      end
    end

    context 'with expired local poll and multiple voters' do
      let(:poll_creator) { create(:actor, local: true, username: 'testuser1') }
      let(:other_voter) { create(:actor, local: true, username: 'testuser2') }
      let(:status) { create(:activity_pub_object, actor: poll_creator, object_type: 'Note') }
      let(:poll) do
        poll = build(:poll, object: status)
        poll.expires_at = 1.hour.ago
        poll.save!(validate: false)
        poll
      end

      before do
        # 作成者が投票
        vote1 = poll.poll_votes.build(actor: poll_creator, choice: 0)
        vote1.save!(validate: false)

        # 別のユーザが投票
        vote2 = poll.poll_votes.build(actor: other_voter, choice: 1)
        vote2.save!(validate: false)
        poll.reload
      end

      it 'creates notifications for both voters' do
        expect do
          described_class.new.perform(poll.id)
        end.to change(Notification, :count).by(2)

        notifications = Notification.where(notification_type: 'poll').order(:id)
        expect(notifications.pluck(:account_id)).to contain_exactly(poll_creator.id, other_voter.id)
      end
    end

    context 'with expired local poll and non-voting creator' do
      let(:creator) { create(:actor, local: true, username: 'creator') }
      let(:voter) { create(:actor, local: true, username: 'voter') }
      let(:status) { create(:activity_pub_object, actor: creator, object_type: 'Note') }
      let(:poll) do
        poll = build(:poll, object: status)
        poll.expires_at = 1.hour.ago
        poll.save!(validate: false)
        poll
      end

      before do
        # 作成者以外が投票
        vote = poll.poll_votes.build(actor: voter, choice: 0)
        vote.save!(validate: false)
        poll.reload
      end

      it 'creates notifications for voter and creator' do
        expect do
          described_class.new.perform(poll.id)
        end.to change(Notification, :count).by(2)

        notifications = Notification.where(notification_type: 'poll')
        expect(notifications.pluck(:account_id)).to contain_exactly(creator.id, voter.id)
      end
    end

    context 'with expired remote poll' do
      let(:remote_user) { create(:actor, :remote, username: 'remoteuser') }
      let(:local_user) { create(:actor, local: true, username: 'localuser') }
      let(:remote_status) { create(:activity_pub_object, actor: remote_user, object_type: 'Note') }
      let(:remote_poll) do
        poll = build(:poll, object: remote_status)
        poll.expires_at = 1.hour.ago
        poll.save!(validate: false)
        poll
      end

      before do
        # ローカルユーザが外部pollに投票
        vote = remote_poll.poll_votes.build(actor: local_user, choice: 0)
        vote.save!(validate: false)
        remote_poll.reload
      end

      it 'notifies local users who voted on remote poll' do
        expect do
          described_class.new.perform(remote_poll.id)
        end.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.notification_type).to eq('poll')
        expect(notification.account).to eq(local_user)
        expect(notification.from_account).to eq(remote_user)
      end

      it 'attempts to fetch remote poll results' do
        # HTTPartyのgetメソッドをスタブ
        response_double = instance_double(HTTParty::Response)
        allow(response_double).to receive_messages(success?: true, parsed_response: {
                                                     'type' => 'Question',
                                                     'oneOf' => [
                                                       { 'name' => 'Remote Option 1', 'replies' => { 'totalItems' => 5 } },
                                                       { 'name' => 'Remote Option 2', 'replies' => { 'totalItems' => 3 } }
                                                     ],
                                                     'votersCount' => 8
                                                   })

        allow(HTTParty).to receive(:get).and_return(response_double)

        described_class.new.perform(remote_poll.id)
        remote_poll.reload

        expect(remote_poll.votes_count).to eq(8)
        expect(remote_poll.voters_count).to eq(8)
      end

      it 'handles remote fetch errors gracefully' do
        # 失敗するHTTPリクエストをスタブ
        response_double = instance_double(HTTParty::Response)
        allow(response_double).to receive_messages(success?: false, code: 500)

        allow(HTTParty).to receive(:get).and_return(response_double)

        # 通知は作成される
        expect do
          described_class.new.perform(remote_poll.id)
        end.to change(Notification, :count).by(1)

        expect(Rails.logger).to have_received(:warn)
          .with(match(/Failed to fetch remote poll results/))
      end
    end

    context 'with non-expired poll' do
      let(:local_user) { create(:actor, local: true, username: 'testuser') }
      let(:status) { create(:activity_pub_object, actor: local_user, object_type: 'Note') }
      let(:active_poll) do
        create(:poll,
               object: status,
               expires_at: 1.hour.from_now)
      end

      before do
        vote = active_poll.poll_votes.build(actor: local_user, choice: 0)
        vote.save!(validate: false)
      end

      it 'does not process active poll and reschedules' do
        expect do
          described_class.new.perform(active_poll.id)
        end.not_to change(Notification, :count)

        expect(Rails.logger).to have_received(:debug).at_least(:once)
      end
    end

    context 'with missing poll' do
      it 'handles RecordNotFound gracefully' do
        expect do
          described_class.new.perform(99_999)
        end.not_to raise_error

        expect(Rails.logger).to have_received(:warn)
          .with(match(/Poll 99999 not found/))
      end
    end
  end
end
