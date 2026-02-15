# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MediaAttachment meta.focus' do
  let(:controller_class) do
    Class.new(Api::BaseController) do
      include MediaSerializer
    end
  end

  let(:controller_instance) { controller_class.new }

  describe 'build_media_meta' do
    it 'includes focus when metadata has focus coordinates' do
      media = create(:media_attachment, metadata: { focus_x: 0.5, focus_y: -0.3 }.to_json)

      result = controller_instance.send(:build_media_meta, media)
      expect(result).to have_key(:focus)
      expect(result[:focus][:x]).to eq(0.5)
      expect(result[:focus][:y]).to eq(-0.3)
    end

    it 'does not include focus when metadata has no focus coordinates' do
      media = create(:media_attachment, metadata: { width: 640, height: 480 }.to_json)

      result = controller_instance.send(:build_media_meta, media)
      expect(result).not_to have_key(:focus)
    end

    it 'does not include focus when metadata is nil' do
      media = create(:media_attachment, metadata: nil)

      result = controller_instance.send(:build_media_meta, media)
      expect(result).not_to have_key(:focus)
    end

    it 'handles focusX/focusY key format' do
      media = create(:media_attachment, metadata: { focusX: 0.0, focusY: 1.0 }.to_json)

      result = controller_instance.send(:build_media_meta, media)
      expect(result).to have_key(:focus)
      expect(result[:focus][:x]).to eq(0.0)
      expect(result[:focus][:y]).to eq(1.0)
    end
  end
end
