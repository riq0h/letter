# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TagSerializer, type: :controller do
  controller(ApplicationController) do
    include TagSerializer # rubocop:disable RSpec/DescribedClass

    def test_action
      render json: { test: 'success' }
    end
  end

  let(:tag) { create(:tag, usage_count: 10) }
  let(:first_actor) { create(:actor) }
  let(:second_actor) { create(:actor) }

  let(:base_url) { Rails.application.config.activitypub.base_url }

  describe '#serialized_tag' do
    context 'with history enabled' do
      before do
        # TagUsageHistory レコードを作成
        TagUsageHistory.create!(tag: tag, date: Date.current, uses: 3, accounts: 2)
        TagUsageHistory.create!(tag: tag, date: 1.day.ago.to_date, uses: 5, accounts: 3)
      end

      it 'returns tag with correct structure' do
        result = controller.send(:serialized_tag, tag, include_history: true)

        expect(result).to include(
          name: tag.name,
          url: "#{base_url}/tags/#{tag.name}",
          history: be_an(Array)
        )
      end

      it 'returns 7 days of history' do
        result = controller.send(:serialized_tag, tag, include_history: true)
        expect(result[:history].length).to eq(7)
      end

      it 'includes correct history data for today' do
        result = controller.send(:serialized_tag, tag, include_history: true)
        today_history = result[:history].first

        expect(today_history).to include(
          day: Date.current.to_time.to_i.to_s,
          uses: '3',
          accounts: '2'
        )
      end

      it 'includes correct history data for yesterday' do
        result = controller.send(:serialized_tag, tag, include_history: true)
        yesterday_history = result[:history][1]

        expect(yesterday_history).to include(
          day: 1.day.ago.to_date.to_time.to_i.to_s,
          uses: '5',
          accounts: '3'
        )
      end

      it 'returns zeros for days without data' do
        result = controller.send(:serialized_tag, tag, include_history: true)
        empty_day = result[:history][2]

        expect(empty_day).to include(
          uses: '0',
          accounts: '0'
        )
      end
    end

    context 'with history disabled' do
      it 'returns tag without history' do
        result = controller.send(:serialized_tag, tag, include_history: false)

        expect(result).to include(
          name: tag.name,
          url: "#{base_url}/tags/#{tag.name}",
          history: []
        )
      end
    end
  end
end
