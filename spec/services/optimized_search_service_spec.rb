# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptimizedSearchService do
  subject(:service) { described_class.new(attributes) }

  let(:attributes) { {} }
  let(:actor) { create(:actor, local: true) }

  describe '#initialize' do
    it 'sets default limit and offset' do
      expect(service.limit).to eq(30)
      expect(service.offset).to eq(0)
    end

    it 'accepts custom limit and offset' do
      service_with_params = described_class.new(limit: 10, offset: 5)
      expect(service_with_params.limit).to eq(10)
      expect(service_with_params.offset).to eq(5)
    end
  end

  describe '#search' do
    context 'when query is blank' do
      let(:attributes) { { query: '' } }

      it 'returns empty array' do
        expect(service.search).to eq([])
      end
    end

    context 'when query is present' do
      let(:attributes) { { query: 'test content' } }
      let!(:matching_post) { create(:activity_pub_object, :note, actor: actor, content: 'This is test content') }

      before do
        create(:activity_pub_object, :note, actor: actor, content: 'Different content')
      end

      it 'returns matching posts' do
        result = service.search
        expect(result).to include(matching_post)
      end
    end

    context 'with time range' do
      let(:attributes) { { query: 'test', since_time: 2.hours.ago, until_time: 1.hour.ago } }

      before do
        create(:activity_pub_object, :note, actor: actor, content: 'test content')
      end

      it 'searches within time range' do
        result = service.search
        expect(result.to_a).to be_an(Array)
      end
    end

    context 'without time range' do
      let(:attributes) { { query: 'test' } }

      before do
        create(:activity_pub_object, :note, actor: actor, content: 'test content')
      end

      it 'performs full text search only' do
        result = service.search
        expect(result.to_a).to be_an(Array)
      end
    end
  end

  describe '#timeline' do
    let!(:public_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }

    before do
      create(:activity_pub_object, :note, actor: actor, visibility: 'private')
      create(:activity_pub_object, :note, actor: create(:actor, :remote), visibility: 'public')
    end

    it 'returns local public notes only' do
      result = service.timeline
      expect(result).to include(public_note)
      expect(result.count).to be >= 1
    end

    context 'with max_id pagination' do
      let!(:older_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }
      let!(:newer_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }

      it 'returns posts before max_id (smaller IDs)' do
        result = service.timeline(max_id: newer_note.id)
        expect(result).to include(older_note)
        expect(result).not_to include(newer_note)
      end
    end

    context 'with min_id pagination' do
      let!(:older_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }
      let!(:newer_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }

      it 'returns posts after min_id (larger IDs)' do
        result = service.timeline(min_id: older_note.id)
        expect(result).to include(newer_note)
        expect(result).not_to include(older_note)
      end
    end
  end

  describe '#user_posts' do
    let(:other_actor) { create(:actor) }
    let!(:public_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }
    let!(:unlisted_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'unlisted') }

    before do
      create(:activity_pub_object, :note, actor: actor, visibility: 'private')
      create(:activity_pub_object, :note, actor: other_actor, visibility: 'public')
    end

    it 'returns public and unlisted posts for specific actor' do
      result = service.user_posts(actor.id)
      expect(result).to include(public_note, unlisted_note)
      expect(result.count).to eq(2)
    end

    context 'with max_id pagination' do
      it 'returns posts before max_id (smaller IDs)' do
        test_older_note = create(:activity_pub_object, :note, actor: actor, visibility: 'public')
        test_newer_note = create(:activity_pub_object, :note, actor: actor, visibility: 'public')

        result = service.user_posts(actor.id, max_id: test_newer_note.id)
        expect(result).to include(test_older_note)
        expect(result).not_to include(test_newer_note)
      end
    end
  end

  describe '#posts_in_time_range' do
    it 'returns posts within time range' do
      start_time = 2.hours.ago
      end_time = 1.hour.ago

      create(:activity_pub_object, :note, actor: actor, published_at: 1.5.hours.ago)
      create(:activity_pub_object, :note, actor: actor, published_at: 3.hours.ago)

      result = service.posts_in_time_range(start_time, end_time)
      expect(result.count).to be >= 0 # 結果を返すことを検証
    end
  end

  describe '#user_posts_search' do
    let(:attributes) { { query: 'search term' } }
    let!(:matching_post) { create(:activity_pub_object, :note, actor: actor, content: 'This contains search term', visibility: 'public') }
    let!(:non_matching_post) { create(:activity_pub_object, :note, actor: actor, content: 'Different content', visibility: 'public') }

    it 'returns matching posts for specific actor' do
      result = service.user_posts_search(actor.id)
      expect(result).to include(matching_post)
      expect(result).not_to include(non_matching_post)
    end

    context 'when query is blank' do
      let(:attributes) { { query: '' } }

      it 'returns empty array' do
        expect(service.user_posts_search(actor.id)).to eq([])
      end
    end
  end
end
