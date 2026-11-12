# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstanceConfig do
  describe '.media_cache_retention_period' do
    it 'defaults to 14 days' do
      expect(described_class.media_cache_retention_period).to eq(14.days)
    end

    it 'uses the configured number of days' do
      described_class.set('media_cache_retention_days', '30')

      expect(described_class.media_cache_retention_period).to eq(30.days)
    end

    it 'falls back to the default for invalid values and clamps large ones' do
      described_class.set('media_cache_retention_days', 'abc')
      expect(described_class.media_cache_retention_period).to eq(14.days)

      described_class.set('media_cache_retention_days', '9999')
      expect(described_class.media_cache_retention_period).to eq(365.days)
    end
  end
end
