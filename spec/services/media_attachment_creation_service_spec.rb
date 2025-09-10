# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MediaAttachmentCreationService do
  let(:user) { create(:actor) }
  let(:service) { described_class.new(user: user, description: 'Test media') }

  describe '#create_from_file' do
    context 'with image file' do
      let(:image_file) do
        fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png'), 'image/png')
      end

      before do
        # テスト用画像ファイルが存在しない場合はスキップ
        skip 'Test image file not found' unless Rails.root.join('spec', 'fixtures', 'files', 'test_image.png').exist?
      end

      it 'creates media attachment with image metadata using libvips' do
        expect do
          media_attachment = service.create_from_file(image_file)

          expect(media_attachment).to be_persisted
          expect(media_attachment.media_type).to eq('image')
          expect(media_attachment.width).to be > 0
          expect(media_attachment.height).to be > 0
          expect(media_attachment.blurhash).to be_present
          expect(media_attachment.processed).to be true
        end.not_to raise_error
      end
    end

    context 'with video file' do
      let(:video_file) do
        fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_video.mp4'), 'video/mp4')
      end

      before do
        # テスト用動画ファイルが存在しない場合はスキップ
        skip 'Test video file not found' unless Rails.root.join('spec', 'fixtures', 'files', 'test_video.mp4').exist?
      end

      it 'creates media attachment with video metadata using libvips' do
        expect do
          media_attachment = service.create_from_file(video_file)

          expect(media_attachment).to be_persisted
          expect(media_attachment.media_type).to eq('video')
          expect(media_attachment.width).to be > 0
          expect(media_attachment.height).to be > 0
          expect(media_attachment.blurhash).to be_present
          expect(media_attachment.processed).to be true
        end.not_to raise_error
      end
    end

    context 'with uploaded file for metadata extraction' do
      let(:uploaded_file) do
        file_path = Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')
        tempfile = Tempfile.new(['test_image', '.png'])
        tempfile.binmode
        tempfile.write(File.read(file_path))
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(
          filename: 'test.png',
          type: 'image/png',
          tempfile: tempfile
        )
      end

      before do
        # テスト画像ファイルが存在する場合のみテスト実行
        skip 'Test image file not found' unless Rails.root.join('spec', 'fixtures', 'files', 'test_image.png').exist?
      end

      it 'extracts image metadata using libvips' do
        expect do
          media_attachment = service.create_from_file(uploaded_file)

          expect(media_attachment).to be_persisted
          expect(media_attachment.width).to be > 0
          expect(media_attachment.height).to be > 0
          expect(media_attachment.blurhash).to be_present
        end.not_to raise_error
      end
    end

    context 'when libvips fails' do
      let(:invalid_file) do
        tempfile = Tempfile.new('invalid.jpg')
        tempfile.write('invalid image data')
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(
          filename: 'invalid.jpg',
          type: 'image/jpeg',
          tempfile: tempfile
        )
      end

      it 'handles libvips errors gracefully' do
        expect do
          media_attachment = service.create_from_file(invalid_file)

          expect(media_attachment).to be_persisted
          expect(media_attachment.media_type).to eq('image')
          # libvipsが失敗した場合、メタデータは空のハッシュが返される
          expect(media_attachment.width).to be_nil
          expect(media_attachment.height).to be_nil
        end.not_to raise_error
      end
    end
  end

  describe 'private methods' do
    describe '#extract_image_metadata' do
      let(:uploaded_file) do
        file_path = Rails.root.join('spec', 'fixtures', 'files', 'test_image.png')
        tempfile = Tempfile.new(['test_image', '.png'])
        tempfile.binmode
        tempfile.write(File.read(file_path))
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(
          filename: 'test.png',
          type: 'image/png',
          tempfile: tempfile
        )
      end

      before do
        skip 'Test image file not found' unless Rails.root.join('spec', 'fixtures', 'files', 'test_image.png').exist?
      end

      it 'returns image dimensions and blurhash' do
        metadata = service.send(:extract_image_metadata, uploaded_file)

        expect(metadata).to include(:width, :height, :blurhash)
        expect(metadata[:width]).to be > 0
        expect(metadata[:height]).to be > 0
        expect(metadata[:blurhash]).to be_present
      end
    end

    describe '#generate_blurhash_from_vips' do
      before do
        skip 'Test image file not found' unless Rails.root.join('spec', 'fixtures', 'files', 'test_image.png').exist?
      end

      it 'generates valid blurhash from vips image' do
        require 'vips'
        image = Vips::Image.new_from_file(Rails.root.join('spec', 'fixtures', 'files', 'test_image.png').to_s)

        blurhash = service.send(:generate_blurhash_from_vips, image)

        expect(blurhash).to be_present
        expect(blurhash).to be_a(String)
        expect(blurhash.length).to be > 0
      end

      it 'handles errors and returns fallback blurhash' do
        require 'vips'
        invalid_image = instance_double(Vips::Image)
        allow(invalid_image).to receive(:width).and_raise(StandardError.new('Test error'))

        blurhash = service.send(:generate_blurhash_from_vips, invalid_image)

        expect(blurhash).to eq('LEHV6nWB2yk8pyo0adR*.7kCMdnj')
      end
    end
  end
end
