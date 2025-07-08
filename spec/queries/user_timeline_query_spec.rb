# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserTimelineQuery do
  subject(:query) { described_class.new(user) }

  let(:user) { create(:actor, local: true) }
  let(:other_user) { create(:actor, local: true) }

  describe '#apply' do
    let(:base_query) { ActivityPubObject.joins(:actor) }

    context 'with blocked users' do
      let(:blocked_user) { create(:actor, local: true) }

      before do
        create(:block, actor: user, target_actor: blocked_user)
      end

      it 'excludes blocked users from query' do
        blocked_post = create(:activity_pub_object, :note, actor: blocked_user)
        normal_post = create(:activity_pub_object, :note, actor: other_user)

        result = query.apply(base_query)
        result_ids = result.pluck(:id)

        expect(result_ids).to include(normal_post.id)
        expect(result_ids).not_to include(blocked_post.id)
      end
    end

    context 'with muted users' do
      let(:muted_user) { create(:actor, local: true) }

      before do
        create(:mute, actor: user, target_actor: muted_user)
      end

      it 'excludes muted users from query' do
        muted_post = create(:activity_pub_object, :note, actor: muted_user)
        normal_post = create(:activity_pub_object, :note, actor: other_user)

        result = query.apply(base_query)
        result_ids = result.pluck(:id)

        expect(result_ids).to include(normal_post.id)
        expect(result_ids).not_to include(muted_post.id)
      end
    end

    context 'with domain blocked users' do
      let(:domain_blocked_user) { create(:actor, :remote, domain: 'blocked.example.com') }

      before do
        create(:domain_block, actor: user, domain: 'blocked.example.com')
      end

      it 'excludes domain blocked users from query' do
        blocked_domain_post = create(:activity_pub_object, :note, actor: domain_blocked_user)
        normal_post = create(:activity_pub_object, :note, actor: other_user)

        result = query.apply(base_query)
        result_ids = result.pluck(:id)

        expect(result_ids).to include(normal_post.id)
        expect(result_ids).not_to include(blocked_domain_post.id)
      end
    end

    context 'with no filters' do
      let(:clean_user) { create(:actor, local: true) }
      let(:clean_query) { described_class.new(clean_user) }

      it 'returns all posts unchanged' do
        post1 = create(:activity_pub_object, :note, actor: other_user)
        post2 = create(:activity_pub_object, :note, actor: user)

        result = clean_query.apply(base_query)
        result_ids = result.pluck(:id)

        expect(result_ids).to include(post1.id, post2.id)
      end
    end

    it 'returns a chainable ActiveRecord relation' do
      result = query.apply(base_query)

      expect(result).to be_a(ActiveRecord::Relation)
      expect { result.limit(1) }.not_to raise_error
      expect { result.where(visibility: 'public') }.not_to raise_error
    end

    it 'preserves original query structure' do
      post = create(:activity_pub_object, :note, actor: other_user, visibility: 'public')

      original_query = base_query.where(visibility: 'public')
      filtered_query = query.apply(original_query)

      expect(filtered_query.to_sql).to include('visibility')
      expect(filtered_query.pluck(:id)).to include(post.id)
    end

    context 'with multiple filter types combined' do
      it 'excludes all filtered user types' do # rubocop:todo RSpec/ExampleLength
        blocked_user = create(:actor, local: true)
        muted_user = create(:actor, local: true)
        domain_blocked_user = create(:actor, :remote, domain: 'blocked.example.com')

        create(:block, actor: user, target_actor: blocked_user)
        create(:mute, actor: user, target_actor: muted_user)
        create(:domain_block, actor: user, domain: 'blocked.example.com')

        blocked_post = create(:activity_pub_object, :note, actor: blocked_user)
        muted_post = create(:activity_pub_object, :note, actor: muted_user)
        domain_blocked_post = create(:activity_pub_object, :note, actor: domain_blocked_user)
        normal_post = create(:activity_pub_object, :note, actor: other_user)

        result_ids = query.apply(base_query).pluck(:id)

        expect(result_ids).to include(normal_post.id)
        expect(result_ids).not_to include(blocked_post.id, muted_post.id, domain_blocked_post.id)
      end
    end

    context 'with empty filter lists' do
      it 'handles empty blocked_actors gracefully' do
        expect(user.blocked_actors).to be_empty
        expect(user.muted_actors).to be_empty
        expect(user.domain_blocks).to be_empty

        post = create(:activity_pub_object, :note, actor: other_user)
        result = query.apply(base_query)

        expect(result.pluck(:id)).to include(post.id)
      end
    end

    context 'when integrating with TimelineBuilderService pattern' do
      it 'works with complex queries like TimelineBuilderService uses' do
        timeline_query = ActivityPubObject.joins(:actor)
                                          .includes(:poll)
                                          .where(object_type: %w[Note Question])
                                          .where(is_pinned_only: false)
                                          .order('objects.id DESC')

        expect { query.apply(timeline_query) }.not_to raise_error

        result = query.apply(timeline_query)
        expect(result).to be_a(ActiveRecord::Relation)
      end
    end
  end
end
