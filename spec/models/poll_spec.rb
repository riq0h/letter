# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Poll do
  let(:local_actor) { create(:actor, local: true) }
  let(:remote_actor) { create(:actor, :remote) }
  let(:local_status) { create(:activity_pub_object, actor: local_actor, object_type: 'Question') }
  let(:remote_status) { create(:activity_pub_object, actor: remote_actor, object_type: 'Question') }

  describe '#remote_poll?' do
    it 'returns false for local poll' do
      poll = create(:poll, object: local_status)
      expect(poll.remote_poll?).to be false
    end

    it 'returns true for remote poll' do
      poll = build(:poll, object: remote_status)
      poll.save!(validate: false)
      expect(poll.remote_poll?).to be true
    end
  end

  describe '#serialize_options' do
    context 'with local poll' do
      let(:poll) { create(:poll, object: local_status) }

      it 'calculates vote counts from PollVote records' do
        vote = poll.poll_votes.build(actor: local_actor, choice: 0)
        vote.save!(validate: false)
        poll.reload

        api = poll.to_mastodon_api
        expect(api[:options][0][:votes_count]).to eq(1)
        expect(api[:options][1][:votes_count]).to eq(0)
      end
    end

    context 'with remote poll' do
      it 'reads vote counts from options JSON' do
        poll = build(:poll, :remote)
        poll.save!(validate: false)

        api = poll.to_mastodon_api
        expect(api[:options][0][:votes_count]).to eq(10)
        expect(api[:options][1][:votes_count]).to eq(5)
      end

      it 'returns 0 when options JSON has no votes_count' do
        poll = build(:poll, object: remote_status,
                            options: [{ 'title' => 'A' }, { 'title' => 'B' }])
        poll.save!(validate: false)

        api = poll.to_mastodon_api
        expect(api[:options][0][:votes_count]).to eq(0)
      end
    end
  end

  describe '#option_votes_count' do
    it 'returns PollVote count for local poll' do
      poll = create(:poll, object: local_status)
      vote = poll.poll_votes.build(actor: local_actor, choice: 1)
      vote.save!(validate: false)

      expect(poll.option_votes_count(0)).to eq(0)
      expect(poll.option_votes_count(1)).to eq(1)
    end

    it 'returns JSON votes_count for remote poll' do
      poll = build(:poll, :remote)
      poll.save!(validate: false)

      expect(poll.option_votes_count(0)).to eq(10)
      expect(poll.option_votes_count(1)).to eq(5)
    end
  end

  describe '#calculate_vote_counts' do
    it 'recalculates from PollVote records for local poll' do
      poll = create(:poll, object: local_status, votes_count: 0, voters_count: 0)
      vote = poll.poll_votes.build(actor: local_actor, choice: 0)
      vote.save!(validate: false)

      poll.save!
      expect(poll.votes_count).to eq(1)
      expect(poll.voters_count).to eq(1)
    end

    it 'preserves remote values for remote poll' do
      poll = build(:poll, :remote)
      poll.save!(validate: false)

      # saveしてもリモートのカウントは上書きされない
      poll.save!
      expect(poll.votes_count).to eq(15)
      expect(poll.voters_count).to eq(15)
    end
  end

  describe '#to_mastodon_api' do
    it 'returns correct structure for local poll' do
      poll = create(:poll, object: local_status)

      api = poll.to_mastodon_api
      expect(api).to include(
        id: poll.id.to_s,
        expired: false,
        multiple: false,
        votes_count: 0,
        emojis: [],
        voted: false,
        own_votes: []
      )
      expect(api[:options]).to be_an(Array)
      expect(api[:options].length).to eq(2)
    end

    it 'returns correct total counts for remote poll' do
      poll = build(:poll, :remote)
      poll.save!(validate: false)

      api = poll.to_mastodon_api
      expect(api[:votes_count]).to eq(15)
      expect(api[:voters_count]).to eq(15)
    end
  end

  describe 'validations for remote polls' do
    it 'allows creating remote poll with past expiry' do
      poll = build(:poll, object: remote_status, expires_at: 1.hour.ago)
      poll.save!(validate: true) # バリデーションをスキップせずに通る
      expect(poll).to be_persisted
    end

    it 'allows creating remote poll with near expiry' do
      poll = build(:poll, object: remote_status, expires_at: 1.minute.from_now)
      poll.save!(validate: true)
      expect(poll).to be_persisted
    end

    it 'still validates expiry for local polls' do
      poll = build(:poll, object: local_status, expires_at: 1.minute.from_now)
      expect(poll).not_to be_valid
      expect(poll.errors[:expires_at]).to be_present
    end
  end

  describe '#vote_for!' do
    let(:poll) { create(:poll, object: local_status) }
    let(:voter) { create(:actor, local: true) }

    it 'creates PollVote and updates counts' do
      result = poll.vote_for!(voter, [0])

      expect(result).to be true
      expect(poll.poll_votes.count).to eq(1)
      poll.reload
      expect(poll.votes_count).to eq(1)
    end

    it 'returns false for expired poll' do
      expired_poll = build(:poll, object: local_status, expires_at: 1.hour.ago)
      expired_poll.save!(validate: false)

      expect(expired_poll.vote_for!(voter, [0])).to be false
    end

    it 'replaces existing vote in single-choice poll' do
      poll.vote_for!(voter, [0])
      poll.vote_for!(voter, [1])

      expect(poll.actor_choices(voter)).to eq([1])
    end
  end
end
