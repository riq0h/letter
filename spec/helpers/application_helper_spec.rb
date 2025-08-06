# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#background_color' do
    before do
      # テスト用のInstanceConfig設定をクリア
      InstanceConfig.delete_all
      Rails.cache.clear
    end

    context 'when background_color is configured in database' do
      it 'returns the configured background color' do
        InstanceConfig.set('background_color', '#ff0000')

        expect(helper.background_color).to eq('#ff0000')
      end
    end

    context 'when background_color is not configured' do
      it 'returns the default color' do
        expect(helper.background_color).to eq('#fdfbfb')
      end
    end

    context 'when database error occurs' do
      it 'returns the default color and handles error' do
        allow(InstanceConfig).to receive(:all_as_hash).and_raise(ActiveRecord::ConnectionNotEstablished)

        expect(helper.background_color).to eq('#fdfbfb')
      end
    end
  end

  describe 'private methods' do
    describe '#load_instance_config' do
      before do
        InstanceConfig.delete_all
        Rails.cache.clear
      end

      it 'loads configuration from database' do
        InstanceConfig.set('background_color', '#blue')
        InstanceConfig.set('instance_name', 'Test Site')

        result = helper.send(:load_instance_config)
        expect(result).to eq({
                               'background_color' => '#blue',
                               'instance_name' => 'Test Site'
                             })
      end

      it 'returns empty hash when no config exists in database' do
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
      end

      it 'returns empty hash and logs error for database errors' do
        allow(InstanceConfig).to receive(:all_as_hash).and_raise(ActiveRecord::ConnectionNotEstablished)

        allow(Rails.logger).to receive(:error).with(/Failed to load config from database/)
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
        expect(Rails.logger).to have_received(:error).with(/Failed to load config from database/)
      end

      it 'handles various database errors gracefully' do
        allow(InstanceConfig).to receive(:all_as_hash).and_raise(StandardError, 'Database connection failed')

        allow(Rails.logger).to receive(:error)
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
        expect(Rails.logger).to have_received(:error).with(/Failed to load config from database.*Database connection failed/)
      end
    end
  end

  describe 'StatusSerializer inclusion' do
    it 'includes StatusSerializer module' do
      expect(helper.class.ancestors).to include(StatusSerializer)
    end
  end
end
