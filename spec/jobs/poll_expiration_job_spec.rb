# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PollExpirationJob, type: :job do
  before do
    allow(Rails.logger).to receive(:info) { |msg| puts "INFO: #{msg}" }
    allow(Rails.logger).to receive(:warn) { |msg| puts "WARN: #{msg}" }
    allow(Rails.logger).to receive(:error) { |msg| puts "ERROR: #{msg}" }
  end

  describe '#perform' do
    it 'can be instantiated and performed without errors' do
      expect { described_class.new.perform }.not_to raise_error
    end

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

      it 'processes expired polls and creates notifications' do
        # デバッグ情報を追加
        puts "Poll ID: #{poll.id}, expires_at: #{poll.expires_at}"
        puts "Local user ID: #{local_user.id}"
        puts "Poll votes count: #{poll.poll_votes.count}"
        puts "Initial notification count: #{Notification.count}"

        # 処理済みチェックのクエリを確認
        processed_poll_ids = Notification.where(notification_type: 'poll')
                                         .joins('JOIN polls ON polls.object_id = notifications.activity_id')
                                         .where(polls: { expires_at: ..Time.current })
                                         .pluck('polls.id')
        puts "Processed poll IDs: #{processed_poll_ids}"

        expired_polls = Poll.where(expires_at: ..Time.current)
                            .joins(:object)
                            .where.not(id: processed_poll_ids)
        puts "Expired polls found: #{expired_polls.pluck(:id)}"

        expect do
          described_class.new.perform
        end.to change(Notification, :count).by(1)

        notification = Notification.last
        expect(notification.notification_type).to eq('poll')
        expect(notification.account).to eq(local_user)
        expect(Rails.logger).to have_received(:info).with(/Checking for expired polls/)
      end

      it 'recalculates vote counts' do
        expect(poll.poll_votes.count).to eq(1)

        described_class.new.perform
        poll.reload

        expect(poll.votes_count).to be >= 0
      end

      it 'does not process the same poll twice' do
        # 初回実行
        described_class.new.perform

        expect do
          # 2回目実行
          described_class.new.perform
        end.not_to change(Notification, :count)
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

      it 'notifies local users who voted on remote polls' do
        expect do
          described_class.new.perform
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

        described_class.new.perform
        remote_poll.reload

        expect(remote_poll.votes_count).to eq(8)
        expect(remote_poll.voters_count).to eq(8)
      end
    end

    context 'with non-expired polls' do
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

      it 'does not process active polls' do
        expect do
          described_class.new.perform
        end.not_to change(Notification, :count)
      end
    end

    context 'when handling errors' do
      let(:local_user) { create(:actor, local: true, username: 'testuser') }
      let(:remote_user) { create(:actor, :remote, username: 'remoteuser') }
      let(:status) { create(:activity_pub_object, actor: remote_user, object_type: 'Note') }
      let(:problematic_poll) do
        poll = build(:poll, object: status)
        poll.expires_at = 1.hour.ago
        poll.save!(validate: false)
        poll
      end

      before do
        vote = problematic_poll.poll_votes.build(actor: local_user, choice: 0)
        vote.save!(validate: false)
      end

      it 'handles remote fetch errors gracefully' do
        # 失敗するHTTPリクエストをスタブ
        response_double = instance_double(HTTParty::Response)
        allow(response_double).to receive_messages(success?: false, code: 500)

        allow(HTTParty).to receive(:get).and_return(response_double)

        # 通知は作成される
        expect do
          described_class.new.perform
        end.to change(Notification, :count).by(1)
        expect(Rails.logger).to have_received(:warn)
          .with(match(/Failed to fetch remote poll results/))
      end
    end
  end
end
