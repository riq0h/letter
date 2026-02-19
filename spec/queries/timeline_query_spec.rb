# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TimelineQuery do
  let(:user) { create(:actor, local: true) }
  let(:other_user) { create(:actor, local: true) }
  let(:query) { described_class.new(user, params) }
  let(:params) { {} }

  describe '#build_home_timeline' do
    before do
      create(:follow, actor: user, target_actor: other_user)
    end

    it 'returns posts from followed users and self' do
      own_post = create(:activity_pub_object, :note, actor: user)
      followed_post = create(:activity_pub_object, :note, actor: other_user)
      stranger_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))

      result = query.build_home_timeline

      expect(result.map(&:id)).to include(own_post.id, followed_post.id)
      expect(result.map(&:id)).not_to include(stranger_post.id)
    end

    it 'includes reblogs from followed users' do
      original_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))
      reblog = Reblog.create!(actor: other_user, object: original_post)

      result = query.build_home_timeline

      expect(result).to include(reblog)
    end

    it 'applies pagination filters' do
      post1 = create(:activity_pub_object, :note, actor: user)
      post2 = create(:activity_pub_object, :note, actor: user)

      query_with_max_id = described_class.new(user, max_id: post2.id)
      result = query_with_max_id.build_home_timeline

      expect(result.map(&:id)).to include(post1.id)
      expect(result.map(&:id)).not_to include(post2.id)
    end

    it 'returns at most limit items' do
      create_list(:activity_pub_object, 10, :note, actor: user)

      query_with_limit = described_class.new(user, limit: 5)
      result = query_with_limit.build_home_timeline

      expect(result.size).to eq(5)
    end

    it 'returns at most limit items when reblogs are mixed in' do
      stranger = create(:actor, local: true)
      create_list(:activity_pub_object, 5, :note, actor: user)
      3.times do
        post = create(:activity_pub_object, :note, actor: stranger)
        Reblog.create!(actor: other_user, object: post)
      end

      query_with_limit = described_class.new(user, limit: 5)
      result = query_with_limit.build_home_timeline

      expect(result.size).to eq(5)
    end
  end

  describe '#build_public_timeline' do
    it 'returns public posts' do
      public_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      private_post = create(:activity_pub_object, :note, actor: user, visibility: 'private')

      result = query.build_public_timeline

      expect(result.map(&:id)).to include(public_post.id)
      expect(result.map(&:id)).not_to include(private_post.id)
    end

    it 'filters to local posts when local_only is true' do
      local_post = create(:activity_pub_object, :note, actor: create(:actor, local: true), visibility: 'public')
      remote_actor = create(:actor, :remote, domain: 'remote.example.com')
      remote_post = create(:activity_pub_object, :note, actor: remote_actor, visibility: 'public')

      query_local = described_class.new(user, local: 'true')
      result = query_local.build_public_timeline

      expect(result.map(&:id)).to include(local_post.id)
      expect(result.map(&:id)).not_to include(remote_post.id)
    end
  end

  describe '#build_hashtag_timeline' do
    let(:tag) { create(:tag, name: 'test') }

    it 'returns posts with the specified hashtag' do
      tagged_post = create(:activity_pub_object, :note, actor: user, visibility: 'public', tags: [tag])
      untagged_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      result = query.build_hashtag_timeline('test')

      expect(result.map(&:id)).to include(tagged_post.id)
      expect(result.map(&:id)).not_to include(untagged_post.id)
    end

    it 'returns empty result for non-existent hashtag' do
      result = query.build_hashtag_timeline('nonexistent')

      expect(result).to be_empty
    end
  end

  describe 'reblog pagination' do
    before do
      create(:follow, actor: user, target_actor: other_user)
    end

    it 'filters reblogs by max_id' do
      old_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))
      old_reblog = Reblog.create!(actor: other_user, object: old_post, created_at: 2.hours.ago)

      new_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))
      new_reblog = Reblog.create!(actor: other_user, object: new_post, created_at: 30.minutes.ago)

      # new_reblogのtimeline_idをmax_idとして使い、それより古いリブログのみ返る
      query_with_max_id = described_class.new(user, max_id: new_reblog.timeline_id)
      result = query_with_max_id.build_home_timeline

      expect(result).to include(old_reblog)
      expect(result).not_to include(new_reblog)
    end

    it 'filters reblogs by since_id' do
      old_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))
      Reblog.create!(actor: other_user, object: old_post, created_at: 2.hours.ago)

      new_post = create(:activity_pub_object, :note, actor: create(:actor, local: true))
      new_reblog = Reblog.create!(actor: other_user, object: new_post, created_at: 30.minutes.ago)

      # 2つのリブログの中間時刻でカーソルを生成
      cursor_id = Letter::Snowflake.generate_at(1.hour.ago)
      query_with_since_id = described_class.new(user, since_id: cursor_id)
      result = query_with_since_id.build_home_timeline

      reblog_results = result.select { |item| item.is_a?(Reblog) }
      expect(reblog_results).to include(new_reblog)
    end

    it 'handles invalid max_id gracefully' do
      post = create(:activity_pub_object, :note, actor: user)

      query_with_bad_id = described_class.new(user, max_id: 'invalid')
      result = query_with_bad_id.build_home_timeline

      # 不正なIDでもクラッシュせず結果を返す
      expect(result).to include(post)
    end
  end

  describe '#apply_pagination_filters' do
    it 'applies max_id filter' do
      oldest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      middle_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      newest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      query_with_max_id = described_class.new(user, max_id: middle_post.id)
      result = query_with_max_id.build_public_timeline

      expect(result.map(&:id)).to include(oldest_post.id)
      expect(result.map(&:id)).not_to include(middle_post.id, newest_post.id)
    end

    it 'applies since_id filter' do
      oldest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      middle_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      newest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      query_with_since_id = described_class.new(user, since_id: middle_post.id)
      result = query_with_since_id.build_public_timeline

      expect(result.map(&:id)).to include(newest_post.id)
      expect(result.map(&:id)).not_to include(oldest_post.id, middle_post.id)
    end

    it 'applies min_id filter' do
      oldest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      middle_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')
      newest_post = create(:activity_pub_object, :note, actor: user, visibility: 'public')

      query_with_min_id = described_class.new(user, min_id: middle_post.id)
      result = query_with_min_id.build_public_timeline

      expect(result.map(&:id)).to include(newest_post.id)
      expect(result.map(&:id)).not_to include(oldest_post.id, middle_post.id)
    end
  end
end
