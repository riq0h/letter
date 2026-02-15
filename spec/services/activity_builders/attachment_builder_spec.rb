# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityBuilders::AttachmentBuilder do
  let(:actor) { create(:actor, local: true) }
  let(:status) { create(:activity_pub_object, :note, actor: actor) }

  describe '#build' do
    it 'includes focalPoint when metadata has focus coordinates' do
      create(:media_attachment,
             actor: actor,
             object: status,
             metadata: { focus_x: 0.5, focus_y: -0.25 }.to_json)

      result = described_class.new(status).build

      expect(result.first).to have_key('focalPoint')
      expect(result.first['focalPoint']).to eq([0.5, -0.25])
    end

    it 'omits focalPoint when metadata has no focus data' do
      create(:media_attachment,
             actor: actor,
             object: status,
             metadata: { width: 640, height: 480 }.to_json)

      result = described_class.new(status).build

      expect(result.first).not_to have_key('focalPoint')
    end

    it 'omits focalPoint when metadata is nil' do
      create(:media_attachment,
             actor: actor,
             object: status,
             metadata: nil)

      result = described_class.new(status).build

      expect(result.first).not_to have_key('focalPoint')
    end
  end
end
