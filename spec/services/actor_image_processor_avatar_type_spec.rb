# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActorImageProcessor do
  let(:actor) { create(:actor, local: true) }
  let(:processor) { described_class.new(actor) }

  # 有効なJPEGバイト列(libvipsが確実に復号できる)
  let(:jpeg_bytes) { Vips::Image.black(20, 20).write_to_buffer('.jpg') }

  describe '#process_avatar_image' do
    it 're-encodes to PNG and reports image/png regardless of the upload format' do
      result = processor.send(:process_avatar_image, StringIO.new(jpeg_bytes),
                              fallback_filename: 'me.jpg', fallback_content_type: 'image/jpeg')

      expect(result[:content_type]).to eq('image/png')
      expect(result[:filename]).to end_with('.png')
    end

    it 'falls back to the original type/filename when the image cannot be decoded' do
      result = processor.send(:process_avatar_image, StringIO.new('not-an-image'),
                              fallback_filename: 'x.jpg', fallback_content_type: 'image/jpeg')

      expect(result[:content_type]).to eq('image/jpeg')
      expect(result[:filename]).to eq('x.jpg')
    end
  end

  describe '#attach_avatar_with_folder' do
    before { allow(processor).to receive(:distribute_profile_update_after_image_change) }

    it 'stores the avatar blob as image/png even when uploaded as jpeg' do
      processor.attach_avatar_with_folder(io: StringIO.new(jpeg_bytes), filename: 'me.jpg', content_type: 'image/jpeg')

      expect(actor.avatar.attached?).to be true
      expect(actor.avatar.blob.content_type).to eq('image/png')
      expect(actor.avatar.blob.filename.to_s).to end_with('.png')
    end
  end
end
