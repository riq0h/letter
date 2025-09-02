# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountStatusesQuery do
  subject(:query) { described_class.new(account, current_user) }

  let(:account) { create(:actor) }
  let(:current_user) { nil }

  describe '#call' do
    let!(:older_status) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
    let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

    it 'returns default relation' do
      result = query.call
      expect(result).to include(older_status, newer_status)
    end
  end

  describe '#pinned_only' do
    let!(:pinned_status) { create(:activity_pub_object, :note, actor: account) }

    before do
      create(:pinned_status, actor: account, object: pinned_status)
      create(:activity_pub_object, :note, actor: account)
    end

    it 'returns only pinned statuses' do
      result = query.pinned_only
      expect(result.map(&:object)).to eq([pinned_status])
    end
  end

  describe '#exclude_replies' do
    let!(:regular_status) { create(:activity_pub_object, :note, actor: account) }
    let!(:reply_status) { create(:activity_pub_object, :note, actor: account, in_reply_to_ap_id: 'https://example.com/status/1') }

    it 'excludes statuses with in_reply_to_ap_id' do
      result = query.exclude_replies.call
      expect(result).to include(regular_status)
      expect(result).not_to include(reply_status)
    end
  end

  describe '#only_media' do
    let!(:status_with_media) { create(:activity_pub_object, :note, actor: account) }
    let!(:status_without_media) { create(:activity_pub_object, :note, actor: account) }

    before do
      create(:media_attachment, object: status_with_media, actor: account)
    end

    it 'returns only statuses with media attachments' do
      result = query.only_media.call
      expect(result).to include(status_with_media)
      expect(result).not_to include(status_without_media)
    end
  end

  describe '#paginate' do
    let!(:first_status) { create(:activity_pub_object, :note, actor: account) }
    let!(:second_status) { create(:activity_pub_object, :note, actor: account) }
    let!(:third_status) { create(:activity_pub_object, :note, actor: account) }

    context 'with max_id' do
      it 'returns statuses before max_id' do
        result = query.paginate(max_id: third_status.id).call
        expect(result).to include(first_status, second_status)
        expect(result).not_to include(third_status)
      end
    end

    context 'with since_id' do
      it 'returns statuses after since_id' do
        result = query.paginate(since_id: first_status.id).call
        expect(result).to include(second_status, third_status)
        expect(result).not_to include(first_status)
      end
    end
  end

  describe '#exclude_pinned' do
    let!(:included_status) { create(:activity_pub_object, :note, actor: account) }
    let!(:excluded_status) { create(:activity_pub_object, :note, actor: account) }

    it 'excludes specified status ids' do
      result = query.exclude_pinned([excluded_status.id]).call
      expect(result).not_to include(excluded_status)
      expect(result).to include(included_status)
    end

    it 'returns all when empty array passed' do
      result = query.exclude_pinned([]).call
      expect(result).to include(included_status, excluded_status)
    end
  end

  describe '#ordered' do
    let!(:older_status) { create(:activity_pub_object, :note, actor: account, published_at: 2.hours.ago) }
    let!(:newer_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

    it 'orders by published_at desc' do
      result = query.ordered.call.to_a
      expect(result.first).to eq(newer_status)
      expect(result.last).to eq(older_status)
    end
  end

  describe '#limit' do
    before do
      create_list(:activity_pub_object, 3, :note, actor: account)
    end

    it 'limits the number of results' do
      result = query.limit(2).call
      expect(result.size).to eq(2)
    end
  end

  describe 'chaining methods' do
    let!(:media_status) { create(:activity_pub_object, :note, actor: account, published_at: 1.hour.ago) }

    before do
      create(:activity_pub_object, :note, actor: account, published_at: 3.hours.ago)
      create(:activity_pub_object, :note, actor: account, in_reply_to_ap_id: 'https://example.com/status/1', published_at: 2.hours.ago)
      create(:media_attachment, object: media_status, actor: account)
    end

    it 'can chain multiple query methods' do
      result = query.exclude_replies
                    .only_media
                    .ordered
                    .limit(10)
                    .call
                    .to_a

      expect(result).to eq([media_status])
    end
  end

  describe 'visibility filtering' do
    let!(:public_status) { create(:activity_pub_object, :note, actor: account, visibility: 'public') }
    let!(:unlisted_status) { create(:activity_pub_object, :note, actor: account, visibility: 'unlisted') }
    let!(:private_status) { create(:activity_pub_object, :note, actor: account, visibility: 'private') }
    let!(:direct_status) { create(:activity_pub_object, :note, actor: account, visibility: 'direct') }

    context 'when current_user is nil (unauthenticated)' do
      let(:current_user) { nil }

      it 'only shows public statuses' do
        result = query.call
        expect(result).to include(public_status)
        expect(result).not_to include(unlisted_status, private_status, direct_status)
      end
    end

    context 'when current_user is the account owner' do
      let(:current_user) { account }

      it 'shows public, unlisted, and private statuses' do
        result = query.call
        expect(result).to include(public_status, unlisted_status, private_status)
        expect(result).not_to include(direct_status)
      end
    end

    context 'when current_user is following the account' do
      let(:current_user) { create(:actor) }

      before do
        create(:follow, actor: current_user, target_actor: account, accepted: true)
      end

      it 'shows public, unlisted, and private statuses' do
        result = query.call
        expect(result).to include(public_status, unlisted_status, private_status)
        expect(result).not_to include(direct_status)
      end
    end

    context 'when current_user is not following the account' do
      let(:current_user) { create(:actor) }

      it 'shows public and unlisted statuses only' do
        result = query.call
        expect(result).to include(public_status, unlisted_status)
        expect(result).not_to include(private_status, direct_status)
      end
    end
  end
end
