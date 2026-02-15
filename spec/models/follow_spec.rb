# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Follow, type: :model do
  subject(:follow) { build(:follow) }

  describe 'associations' do
    it { is_expected.to belong_to(:actor) }
    it { is_expected.to belong_to(:target_actor) }
  end

  describe 'scopes' do
    let!(:accepted_follow) { create(:follow, :accepted) }
    let!(:pending_follow) { create(:follow) }
    let!(:local_follow) { create(:follow, :local) }

    it '.accepted returns only accepted follows' do
      expect(described_class.accepted).to include(accepted_follow)
      expect(described_class.accepted).not_to include(pending_follow)
    end

    it '.pending returns only pending follows' do
      expect(described_class.pending).to include(pending_follow)
      expect(described_class.pending).not_to include(accepted_follow)
    end

    it '.local returns only local follows' do
      expect(described_class.local).to include(local_follow)
    end
  end

  describe 'status methods' do
    it '#accepted? returns true when accepted' do
      follow.accepted = true
      expect(follow.accepted?).to be true
    end

    it '#accepted? returns false when not accepted' do
      follow.accepted = false
      expect(follow.accepted?).to be false
    end

    it '#pending? returns true when not accepted' do
      follow.accepted = false
      expect(follow.pending?).to be true
    end

    it '#pending? returns false when accepted' do
      follow.accepted = true
      expect(follow.pending?).to be false
    end
  end

  describe 'type methods' do
    it '#local_follow? returns true for local follows' do
      local_follow = create(:follow, :local, :accepted)
      expect(local_follow.local_follow?).to be true
    end
  end

  describe '#accept!' do
    it 'sets accepted to true' do
      test_follow = create(:follow)
      test_follow.accept!
      expect(test_follow.accepted).to be true
      expect(test_follow.persisted?).to be true
    end
  end

  describe '#reject!' do
    it 'destroys the follow record' do
      test_follow = create(:follow)
      expect { test_follow.reject! }.to change(described_class, :count).by(-1)
    end
  end

  describe '#unfollow!' do
    it 'destroys the follow record' do
      test_follow = create(:follow, :accepted)
      expect { test_follow.unfollow! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'URL methods' do
    it '#activitypub_url returns the AP ID' do
      follow.ap_id = 'https://example.com/follows/123'
      expect(follow.activitypub_url).to eq('https://example.com/follows/123')
    end

    it '#follow_activity_url returns the follow activity URL' do
      follow.follow_activity_ap_id = 'https://example.com/activities/456'
      expect(follow.follow_activity_url).to eq('https://example.com/activities/456')
    end
  end

  describe 'validations' do
    context 'when preventing self-follow' do
      it 'prevents following self' do
        actor = create(:actor)
        follow = build(:follow, actor: actor, target_actor: actor)

        expect(follow).not_to be_valid
        expect(follow.errors[:target_actor]).to include('cannot follow yourself')
      end

      it 'allows following other actors' do
        actor1 = create(:actor)
        actor2 = create(:actor, :remote)
        follow = build(:follow, actor: actor1, target_actor: actor2)
        expect(follow).to be_valid
      end
    end
  end
end
