# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MergedTimeline do
  let(:user) { create(:actor) }
  let(:other_user) { create(:actor) }

  describe '.merge' do
    it 'creates MergedTimeline from collections' do
      status = create(:activity_pub_object, actor: user)
      reblog = create(:reblog, actor: other_user, object: status)

      merged = described_class.merge([status], [reblog], 10)
      expect(merged).to be_a(described_class)
      expect(merged.count).to eq(1)
    end
  end

  describe '#initialize' do
    it 'merges statuses and reblogs chronologically' do
      old_status = create(:activity_pub_object, actor: user, published_at: 2.hours.ago)
      new_status = create(:activity_pub_object, actor: user, published_at: 1.hour.ago)
      reblog = create(:reblog, actor: other_user, object: old_status, created_at: 30.minutes.ago)

      merged = described_class.new([old_status, new_status], [reblog], 10)

      expect(merged.items.first).to eq(reblog)
      expect(merged.items.second).to eq(new_status)
      expect(merged.items).not_to include(old_status) # Reblog takes precedence
    end

    it 'handles empty collections' do
      merged = described_class.new([], [], 10)
      expect(merged.items).to be_empty
    end

    it 'respects limit parameter' do
      statuses = create_list(:activity_pub_object, 5, actor: user)
      merged = described_class.new(statuses, [], 3)
      expect(merged.count).to eq(3)
    end

    it 'removes duplicates when reblog exists for status' do
      status = create(:activity_pub_object, actor: user)
      reblog = create(:reblog, actor: other_user, object: status)

      merged = described_class.new([status], [reblog], 10)
      expect(merged.count).to eq(1)
      expect(merged.items.first).to eq(reblog)
    end
  end

  describe '#count' do
    it 'returns number of merged items' do
      statuses = create_list(:activity_pub_object, 3, actor: user)
      merged = described_class.new(statuses, [], 10)
      expect(merged.count).to eq(3)
    end
  end

  describe '#empty?' do
    it 'returns true when no items' do
      merged = described_class.new([], [], 10)
      expect(merged).to be_empty
    end

    it 'returns false when items exist' do
      status = create(:activity_pub_object, actor: user)
      merged = described_class.new([status], [], 10)
      expect(merged).not_to be_empty
    end
  end

  describe '#to_a' do
    it 'returns items as array' do
      status = create(:activity_pub_object, actor: user)
      merged = described_class.new([status], [], 10)
      expect(merged.to_a).to eq([status])
    end
  end

  describe 'Enumerable methods' do
    let(:statuses) { create_list(:activity_pub_object, 3, actor: user) }
    let(:merged) { described_class.new(statuses, [], 10) }

    it 'supports each' do
      count = 0
      merged.each { |_item| count += 1 }
      expect(count).to eq(3)
    end

    it 'supports map' do
      ids = merged.map(&:id)
      expect(ids).to match_array(statuses.map(&:id))
    end

    it 'supports first' do
      expect(merged.first).to be_a(ActivityPubObject)
    end

    it 'supports last' do
      expect(merged.last).to be_a(ActivityPubObject)
    end
  end

  describe '#to_s' do
    it 'returns string representation' do
      status = create(:activity_pub_object, actor: user)
      merged = described_class.new([status], [], 10)
      expect(merged.to_s).to eq('MergedTimeline(1 items)')
    end
  end

  describe '#==' do
    it 'returns true for same items and limit' do
      status = create(:activity_pub_object, actor: user)
      merged1 = described_class.new([status], [], 10)
      merged2 = described_class.new([status], [], 10)
      expect(merged1).to eq(merged2)
    end

    it 'returns false for different items' do
      status1 = create(:activity_pub_object, actor: user)
      status2 = create(:activity_pub_object, actor: user)
      merged1 = described_class.new([status1], [], 10)
      merged2 = described_class.new([status2], [], 10)
      expect(merged1).not_to eq(merged2)
    end

    it 'returns false for different limits' do
      status = create(:activity_pub_object, actor: user)
      merged1 = described_class.new([status], [], 10)
      merged2 = described_class.new([status], [], 5)
      expect(merged1).not_to eq(merged2)
    end

    it 'returns false for objects of other classes' do
      status = create(:activity_pub_object, actor: user)
      merged = described_class.new([status], [], 10)
      expect(merged).not_to eq([status])
    end
  end

  describe 'chronological ordering' do
    it 'sorts items by timestamp in descending order' do
      oldest_status = create(:activity_pub_object, actor: user, published_at: 3.hours.ago)
      newest_status = create(:activity_pub_object, actor: user, published_at: 1.hour.ago)
      middle_reblog = create(:reblog, actor: other_user,
                                      object: create(:activity_pub_object, actor: user),
                                      created_at: 2.hours.ago)

      merged = described_class.new([oldest_status, newest_status], [middle_reblog], 10)

      expect(merged.items[0]).to eq(newest_status)
      expect(merged.items[1]).to eq(middle_reblog)
      expect(merged.items[2]).to eq(oldest_status)
    end
  end

  describe 'immutability' do
    it 'is immutable' do
      status = create(:activity_pub_object, actor: user)
      merged = described_class.new([status], [], 10)
      expect(merged).to be_frozen
    end
  end
end
