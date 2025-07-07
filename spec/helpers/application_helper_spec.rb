# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#background_color' do
    let(:config_file_path) { Rails.root.join('config', 'instance_config.yml') }

    before do
      # Clean up any existing test config file
      FileUtils.rm_f(config_file_path)
    end

    after do
      # Clean up test config file
      FileUtils.rm_f(config_file_path)
    end

    context 'when config file exists with background_color' do
      it 'returns the configured background color' do
        config_data = { 'background_color' => '#ff0000' }
        File.write(config_file_path, config_data.to_yaml)

        expect(helper.background_color).to eq('#ff0000')
      end
    end

    context 'when config file exists without background_color' do
      it 'returns the default color' do
        config_data = { 'other_setting' => 'value' }
        File.write(config_file_path, config_data.to_yaml)

        expect(helper.background_color).to eq('#fdfbfb')
      end
    end

    context 'when config file does not exist' do
      it 'returns the default color' do
        expect(helper.background_color).to eq('#fdfbfb')
      end
    end

    context 'when config file is malformed' do
      it 'returns the default color and handles error' do
        File.write(config_file_path, 'invalid: yaml: content: [')

        # YAML parse error will be handled and default returned
        expect(helper.background_color).to eq('#fdfbfb')
      end
    end

    context 'when config file is empty' do
      it 'returns the default color' do
        File.write(config_file_path, '')

        expect(helper.background_color).to eq('#fdfbfb')
      end
    end

    context 'when YAML returns nil' do
      it 'returns the default color' do
        allow(YAML).to receive(:load_file).and_return(nil)
        File.write(config_file_path, '')

        expect(helper.background_color).to eq('#fdfbfb')
      end
    end
  end

  describe 'private methods' do
    describe '#load_instance_config' do
      let(:config_file_path) { Rails.root.join('config', 'instance_config.yml') }

      before do
        FileUtils.rm_f(config_file_path)
      end

      after do
        FileUtils.rm_f(config_file_path)
      end

      it 'loads valid YAML configuration' do
        config_data = { 'background_color' => '#blue', 'site_name' => 'Test Site' }
        File.write(config_file_path, config_data.to_yaml)

        result = helper.send(:load_instance_config)
        expect(result).to eq(config_data)
      end

      it 'returns empty hash when file does not exist' do
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
      end

      it 'returns empty hash and logs error for invalid YAML' do
        File.write(config_file_path, 'invalid: yaml: [unclosed')

        allow(Rails.logger).to receive(:error).with(/Failed to load config/)
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
        expect(Rails.logger).to have_received(:error).with(/Failed to load config/)
      end

      it 'handles file read errors gracefully' do
        File.write(config_file_path, 'valid: config')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(config_file_path).and_return(true)
        allow(YAML).to receive(:safe_load_file).and_raise(Errno::EACCES, 'Permission denied')

        allow(Rails.logger).to receive(:error).with(/Failed to load config.*Permission denied/)
        result = helper.send(:load_instance_config)
        expect(result).to eq({})
        expect(Rails.logger).to have_received(:error).with(/Failed to load config.*Permission denied/)
      end

      it 'returns empty hash when YAML file contains only null' do
        File.write(config_file_path, '---')

        result = helper.send(:load_instance_config)
        expect(result).to eq({})
      end
    end
  end

  describe 'StatusSerializer inclusion' do
    it 'includes StatusSerializer module' do
      expect(helper.class.ancestors).to include(StatusSerializer)
    end
  end
end
