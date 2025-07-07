# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagSerializer, type: :controller do
  controller(ApplicationController) do
    include described_class

    def test_action
      render json: { test: 'success' }
    end
  end

  let(:tag) { create(:tag, usage_count: 10) }
  let(:first_actor) { create(:actor) }
  let(:second_actor) { create(:actor) }

  before do
    allow(controller.request).to receive(:base_url).and_return('https://example.com')
  end

  describe '#serialized_tag' do
    context 'with history enabled' do
      before do
        first_today_object = create(:activity_pub_object, actor: first_actor, published_at: Time.current)
        second_today_object = create(:activity_pub_object, actor: second_actor, published_at: Time.current)
        yesterday_object = create(:activity_pub_object, actor: first_actor, published_at: 1.day.ago)

        create(:object_tag, object: first_today_object, tag: tag)
        create(:object_tag, object: second_today_object, tag: tag)
        create(:object_tag, object: yesterday_object, tag: tag)
      end

      it 'returns tag with correct structure' do
        result = controller.send(:serialized_tag, tag, include_history: true)

        expect(result).to include(
          name: tag.name,
          url: "https://example.com/tags/#{tag.name}",
          history: be_an(Array)
        )
      end

      it 'includes correct history data' do
        result = controller.send(:serialized_tag, tag, include_history: true)
        history = result[:history].first

        expect(history).to include(
          day: Date.current.to_s,
          uses: tag.usage_count.to_s,
          accounts: '2'
        )
      end
    end

    context 'with history disabled' do
      it 'returns tag without history' do
        result = controller.send(:serialized_tag, tag, include_history: false)

        expect(result).to include(
          name: tag.name,
          url: "https://example.com/tags/#{tag.name}",
          history: []
        )
      end
    end
  end

  describe '#calculate_tag_accounts_count' do
    context 'with multiple actors posting today' do
      before do
        first_post_by_first_actor = create(:activity_pub_object, actor: first_actor, published_at: Time.current)
        post_by_second_actor = create(:activity_pub_object, actor: second_actor, published_at: Time.current)
        second_post_by_first_actor = create(:activity_pub_object, actor: first_actor, published_at: Time.current)

        create(:object_tag, object: first_post_by_first_actor, tag: tag)
        create(:object_tag, object: post_by_second_actor, tag: tag)
        create(:object_tag, object: second_post_by_first_actor, tag: tag)
      end

      it 'returns unique actor count for today' do
        count = controller.send(:calculate_tag_accounts_count, tag)
        expect(count).to eq(2)
      end
    end

    context 'with posts from different days' do
      let!(:today_object) { create(:activity_pub_object, actor: first_actor, published_at: Time.current) }
      let!(:yesterday_object) { create(:activity_pub_object, actor: second_actor, published_at: 1.day.ago) }

      before do
        create(:object_tag, object: today_object, tag: tag)
        create(:object_tag, object: yesterday_object, tag: tag)
      end

      it 'only counts actors from today' do
        count = controller.send(:calculate_tag_accounts_count, tag)
        expect(count).to eq(1)
      end
    end

    context 'with no posts today' do
      let!(:yesterday_object) { create(:activity_pub_object, actor: first_actor, published_at: 1.day.ago) }

      before do
        create(:object_tag, object: yesterday_object, tag: tag)
      end

      it 'returns zero' do
        count = controller.send(:calculate_tag_accounts_count, tag)
        expect(count).to eq(0)
      end
    end

    context 'when database error occurs' do
      before do
        allow(tag).to receive(:object_tags).and_raise(StandardError, 'Database error')
        allow(Rails.logger).to receive(:error)
      end

      it 'returns fallback value and logs error' do
        count = controller.send(:calculate_tag_accounts_count, tag)

        expect(count).to eq(1)
        expect(Rails.logger).to have_received(:error).with(
          'Failed to calculate tag accounts count: Database error'
        )
      end
    end
  end
end
