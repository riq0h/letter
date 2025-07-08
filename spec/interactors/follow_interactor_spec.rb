# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FollowInteractor do
  let(:actor) { create(:actor) }
  let(:target_actor) { create(:actor) }
  let(:remote_actor) do
    create(:actor, :remote,
           domain: 'example.com',
           local: false,
           ap_id: 'https://example.com/users/remote',
           inbox_url: 'https://example.com/users/remote/inbox',
           outbox_url: 'https://example.com/users/remote/outbox',
           public_key: 'test-public-key')
  end

  describe '.follow' do
    it 'follows a local actor successfully' do
      result = described_class.follow(actor, target_actor)

      expect(result).to be_success
      expect(result.follow).to be_a(Follow)
      expect(result.follow.actor).to eq(actor)
      expect(result.follow.target_actor).to eq(target_actor)
    end

    it 'returns existing follow if already following' do
      existing_follow = create(:follow, actor: actor, target_actor: target_actor)

      result = described_class.follow(actor, target_actor)

      expect(result).to be_success
      expect(result.follow).to eq(existing_follow)
    end

    it 'follows a remote actor' do
      allow(SendFollowJob).to receive(:perform_later)

      result = described_class.follow(actor, remote_actor)

      expect(result).to be_success
      expect(result.follow.accepted).to be(false) # Remote follows start as pending
      expect(SendFollowJob).to have_received(:perform_later).at_least(:once)
    end

    it 'returns failure when target actor not found' do
      result = described_class.follow(actor, 'nonexistent@example.com')

      expect(result).to be_failure
      expect(result.error).to eq('Target actor not found')
    end

    context 'when following by ActivityPub URI' do
      let(:uri) { 'https://example.com/users/testuser' }

      before do
        interactor = described_class.new(actor)
        allow(described_class).to receive(:new).with(actor).and_return(interactor)
        allow(interactor).to receive(:fetch_remote_actor_by_uri)
          .with(uri)
          .and_return(remote_actor)
      end

      it 'resolves and follows the actor' do
        result = described_class.follow(actor, uri)

        expect(result).to be_success
        expect(result.follow.target_actor).to eq(remote_actor)
      end
    end

    context 'when following by acct format' do
      let(:acct) { 'testuser@example.com' }

      before do
        interactor = described_class.new(actor)
        allow(described_class).to receive(:new).with(actor).and_return(interactor)
        allow(interactor).to receive(:find_or_fetch_actor)
          .with('testuser', 'example.com')
          .and_return(remote_actor)
      end

      it 'resolves and follows the actor' do
        result = described_class.follow(actor, acct)

        expect(result).to be_success
        expect(result.follow.target_actor).to eq(remote_actor)
      end
    end
  end

  describe '.unfollow' do
    let!(:follow) { create(:follow, actor: actor, target_actor: target_actor) }

    it 'unfollows an actor successfully' do
      result = described_class.unfollow(actor, target_actor)

      expect(result).to be_success
      expect(result.follow).to eq(follow)
    end

    it 'returns failure when follow relationship not found' do
      other_actor = create(:actor)

      result = described_class.unfollow(actor, other_actor)

      expect(result).to be_failure
      expect(result.error).to eq('Follow relationship not found')
    end

    it 'returns failure when target actor not found' do
      result = described_class.unfollow(actor, 'nonexistent@example.com')

      expect(result).to be_failure
      expect(result.error).to eq('Target actor not found')
    end
  end

  describe '#follow' do
    subject(:interactor) { described_class.new(actor) }

    it 'creates follow with correct attributes for local actor' do
      result = interactor.follow(target_actor)

      expect(result).to be_success
      follow = result.follow
      expect(follow.actor).to eq(actor)
      expect(follow.target_actor).to eq(target_actor)
      expect(follow.accepted).to be(true) # Local follows are auto-accepted
      expect(follow.ap_id).to include('#follows/')
    end

    it 'creates follow with pending status for remote actor' do
      result = interactor.follow(remote_actor)

      expect(result).to be_success
      follow = result.follow
      expect(follow.accepted).to be(false) # Remote follows start pending
    end

    context 'when actor requires manual approval' do
      let(:manual_approval_actor) { create(:actor, manually_approves_followers: true, local: true) }

      it 'creates follow with pending status' do
        result = interactor.follow(manual_approval_actor)

        expect(result).to be_success
        follow = result.follow
        expect(follow.accepted).to be(false)
        expect(follow.accepted_at).to be_nil
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
end
