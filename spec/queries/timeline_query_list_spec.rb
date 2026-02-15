# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimelineQuery do
  let(:user) { create(:actor, local: true) }

  describe '#build_list_timeline' do
    let(:list) { create(:list, actor: user) }
    let(:member1) { create(:actor, local: true) }
    let(:member2) { create(:actor, local: true) }

    before do
      create(:list_membership, list: list, actor: member1)
      create(:list_membership, list: list, actor: member2)
    end

    it 'returns posts from list members' do
      post1 = create(:activity_pub_object, :note, actor: member1, visibility: 'public')
      post2 = create(:activity_pub_object, :note, actor: member2, visibility: 'public')
      stranger_post = create(:activity_pub_object, :note, actor: create(:actor, local: true), visibility: 'public')

      query = described_class.new(user, {})
      result = query.build_list_timeline(list)

      expect(result.map(&:id)).to include(post1.id, post2.id)
      expect(result.map(&:id)).not_to include(stranger_post.id)
    end

    it 'returns empty result for list with no members' do
      empty_list = create(:list, actor: user)

      query = described_class.new(user, {})
      result = query.build_list_timeline(empty_list)

      expect(result).to be_empty
    end

    it 'applies pagination filters' do
      post1 = create(:activity_pub_object, :note, actor: member1, visibility: 'public')
      post2 = create(:activity_pub_object, :note, actor: member1, visibility: 'public')

      query = described_class.new(user, max_id: post2.id)
      result = query.build_list_timeline(list)

      expect(result.map(&:id)).to include(post1.id)
      expect(result.map(&:id)).not_to include(post2.id)
    end
  end
end
