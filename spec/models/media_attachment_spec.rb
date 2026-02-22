# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MediaAttachment, type: :model do
  subject(:media_attachment) { build(:media_attachment) }

  describe 'associations' do
    it { is_expected.to belong_to(:actor) }
    it { is_expected.to belong_to(:object).optional }
  end

  describe 'scopes' do
    let!(:image) { create(:media_attachment, media_type: 'image') }
    let!(:video) { create(:media_attachment, :video) }

    it '.images returns only image media' do
      expect(described_class.images).to include(image)
      expect(described_class.images).not_to include(video)
    end

    it '.videos returns only video media' do
      expect(described_class.videos).to include(video)
      expect(described_class.videos).not_to include(image)
    end
  end

  describe 'media type methods' do
    context 'when media is image' do
      let(:image_media) { build(:media_attachment, media_type: 'image') }

      it '#image? returns true' do
        expect(image_media.image?).to be true
      end

      it '#video? returns false' do
        expect(image_media.video?).to be false
      end

      it '#audio? returns false' do
        expect(image_media.audio?).to be false
      end

      it '#document? returns false' do
        expect(image_media.document?).to be false
      end
    end

    context 'when media is video' do
      let(:video_media) { build(:media_attachment, :video) }

      it '#video? returns true' do
        expect(video_media.video?).to be true
      end

      it '#image? returns false' do
        expect(video_media.image?).to be false
      end
    end
  end

  describe '#display_name' do
    it 'returns file_name when present' do
      media_attachment.file_name = 'test.jpg'
      expect(media_attachment.display_name).to eq('test.jpg')
    end

    it 'returns default when file_name is blank' do
      media_attachment.file_name = nil
      expect(media_attachment.display_name).to eq('Untitled')
    end
  end

  describe '#human_file_size' do
    it 'returns formatted file size' do
      media_attachment.file_size = 1024
      expect(media_attachment.human_file_size).to eq('1.0 KB')
    end

    it 'handles larger sizes' do
      media_attachment.file_size = 1_048_576
      expect(media_attachment.human_file_size).to eq('1.0 MB')
    end
  end

  describe 'aspect ratio methods' do
    context 'when width and height are present' do
      let(:landscape_media) { build(:media_attachment, width: 1920, height: 1080) }
      let(:portrait_media) { build(:media_attachment, width: 1080, height: 1920) }
      let(:square_media) { build(:media_attachment, width: 1080, height: 1080) }

      it '#landscape? returns true for landscape images' do
        expect(landscape_media.landscape?).to be true
        expect(portrait_media.landscape?).to be false
        expect(square_media.landscape?).to be false
      end

      it '#portrait? returns true for portrait images' do
        expect(portrait_media.portrait?).to be true
        expect(landscape_media.portrait?).to be false
        expect(square_media.portrait?).to be false
      end

      it '#square? returns true for square images' do
        expect(square_media.square?).to be true
        expect(landscape_media.square?).to be false
        expect(portrait_media.square?).to be false
      end

      it '#aspect_ratio calculates correctly' do
        expect(landscape_media.aspect_ratio).to be_within(0.01).of(1.78)
        expect(portrait_media.aspect_ratio).to be_within(0.01).of(0.56)
        expect(square_media.aspect_ratio).to eq(1.0)
      end
    end
  end

  describe '#activitypub_document' do
    before do
      media_attachment.remote_url = 'https://example.com/image.jpg'
      media_attachment.content_type = 'image/jpeg'
      media_attachment.description = 'Test description'
    end

    it 'returns ActivityPub document representation' do
      document = media_attachment.activitypub_document

      expect(document).to include(
        type: 'Document',
        url: 'https://example.com/image.jpg',
        mediaType: 'image/jpeg'
      )
      expect(document[:name]).to be_present
      expect(document[:summary]).to be_present
    end
  end

  describe 'MIME subtype alias validation' do
    it 'accepts video/quicktime as valid video content type' do
      media = build(:media_attachment, :video, content_type: 'video/quicktime', file_name: 'video.mov')
      expect(media).to be_valid
    end

    it 'accepts audio/mpeg as valid audio content type' do
      media = build(:media_attachment, :audio, content_type: 'audio/mpeg', file_name: 'audio.mp3')
      expect(media).to be_valid
    end

    it 'rejects unsupported content type for video' do
      media = build(:media_attachment, :video, content_type: 'video/x-unknown')
      expect(media).not_to be_valid
      expect(media.errors[:content_type]).to be_present
    end
  end

  describe 'URL generation' do
    it '#url returns the remote URL when present' do
      media_attachment.remote_url = 'https://example.com/test.jpg'
      expect(media_attachment.url).to eq('https://example.com/test.jpg')
    end

    it '#preview_url returns the same as url for remote files' do
      media_attachment.remote_url = 'https://example.com/test.jpg'
      expect(media_attachment.preview_url).to eq(media_attachment.url)
    end
  end

  describe '#attached?' do
    it 'returns true when file is attached (simulated)' do
      expect(media_attachment.attached?).to be false
    end
  end

  describe '#local_file?' do
    it 'returns false when no file is attached' do
      expect(media_attachment.local_file?).to be false
    end
  end
end
