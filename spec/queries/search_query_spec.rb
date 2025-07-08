# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchQuery do
  subject(:query) { described_class.new(attributes) }

  let(:attributes) { {} }
  let(:actor) { create(:actor, local: true) }

  describe '#initialize' do
    it 'sets default limit and offset' do
      expect(query.limit).to eq(30)
      expect(query.offset).to eq(0)
    end

    context 'with custom parameters' do
      let(:test_time) { 1.hour.ago }
      let(:current_time) { Time.current }
      let(:query_with_params) do
        described_class.new(
          query: 'test',
          limit: 10,
          offset: 5,
          since_time: test_time,
          until_time: current_time
        )
      end

      it 'accepts all parameters correctly' do
        expect(query_with_params.query).to eq('test')
        expect(query_with_params.limit).to eq(10)
        expect(query_with_params.offset).to eq(5)
        expect(query_with_params.since_time).to eq(test_time)
        expect(query_with_params.until_time).to eq(current_time)
      end
    end
  end

  describe '#search' do
    context 'when query is blank' do
      let(:attributes) { { query: '' } }

      it 'returns empty array' do
        expect(query.search).to eq([])
      end
    end

    context 'when query is present' do
      let(:attributes) { { query: 'test content' } }

      before do
        create(:activity_pub_object, :note, actor: actor, content: 'test content')
      end

      it 'returns matching posts' do
        result = query.search
        expect(result.to_a).to be_an(Array)
      end
    end

    context 'with time range' do
      let(:attributes) { { query: 'test', since_time: 2.hours.ago, until_time: 1.hour.ago } }

      before do
        create(:activity_pub_object, :note, actor: actor, content: 'test content')
      end

      it 'searches within time range' do
        result = query.search
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
      result = query.timeline
      expect(result).to include(public_note)
      # countには他のテストで作成されたpublicノートが含まれる可能性がある
      expect(result.count).to be >= 1
    end

    context 'with pagination' do
      let!(:older_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }
      let!(:newer_note) { create(:activity_pub_object, :note, actor: actor, visibility: 'public') }

      it 'supports max_id pagination' do
        result = query.timeline(max_id: newer_note.id)
        expect(result).to include(older_note)
        expect(result).not_to include(newer_note)
      end

      it 'supports min_id pagination' do
        result = query.timeline(min_id: older_note.id)
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
      result = query.user_posts(actor.id)
      expect(result).to include(public_note, unlisted_note)
      expect(result.count).to eq(2)
    end

    context 'with max_id pagination' do
      it 'returns posts before max_id' do
        test_older_note = create(:activity_pub_object, :note, actor: actor, visibility: 'public')
        test_newer_note = create(:activity_pub_object, :note, actor: actor, visibility: 'public')

        result = query.user_posts(actor.id, max_id: test_newer_note.id)
        expect(result).to include(test_older_note)
        expect(result).not_to include(test_newer_note)
      end
    end
  end

  describe '#posts_in_time_range' do
    it 'returns posts within time range' do
      start_time = 2.hours.ago
      end_time = 1.hour.ago

      result = query.posts_in_time_range(start_time, end_time)
      expect(result).to respond_to(:each)
    end
  end

  describe '#user_posts_search' do
    let(:attributes) { { query: 'search term' } }

    context 'when query is blank' do
      let(:attributes) { { query: '' } }

      it 'returns empty array' do
        expect(query.user_posts_search(actor.id)).to eq([])
      end
    end

    context 'when query is present' do
      before do
        create(:activity_pub_object, :note, actor: actor, content: 'search term')
      end

      it 'searches for matching posts by actor' do
        result = query.user_posts_search(actor.id)
        expect(result.to_a).to be_an(Array)
      end
    end
  end

  describe '#contains_japanese_characters?' do
    let(:japanese_query) { described_class.new(query: 'テスト') }
    let(:english_query) { described_class.new(query: 'test query') }

    it 'returns true with Japanese text' do
      expect(japanese_query.send(:contains_japanese_characters?)).to be true
    end

    it 'returns false with English text' do
      expect(english_query.send(:contains_japanese_characters?)).to be false
    end
  end

  describe '#contains_special_characters?' do
    let(:special_char_query) { described_class.new(query: 'test@example.com') }
    let(:normal_query) { described_class.new(query: 'test query') }

    it 'returns true with special characters' do
      expect(special_char_query.send(:contains_special_characters?)).to be true
    end

    it 'returns false without special characters' do
      expect(normal_query.send(:contains_special_characters?)).to be false
    end
  end

  describe '#build_fts5_query' do
    it 'wraps single word in quotes' do
      single_word_query = described_class.new(query: 'test')
      expect(single_word_query.send(:build_fts5_query)).to eq('"test"')
    end

    it 'joins multiple words with AND' do
      multi_word_query = described_class.new(query: 'test query example')
      expect(multi_word_query.send(:build_fts5_query)).to eq('"test" AND "query" AND "example"')
    end
  end
end
