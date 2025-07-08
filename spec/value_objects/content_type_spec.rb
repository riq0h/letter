# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContentType do
  describe '.from_filename' do
    it 'detects JPEG images' do
      content_type = described_class.from_filename('image.jpg')
      expect(content_type.mime_type).to eq('image/jpeg')
    end

    it 'detects PNG images' do
      content_type = described_class.from_filename('image.png')
      expect(content_type.mime_type).to eq('image/png')
    end

    it 'detects GIF images' do
      content_type = described_class.from_filename('image.gif')
      expect(content_type.mime_type).to eq('image/gif')
    end

    it 'detects WebP images' do
      content_type = described_class.from_filename('image.webp')
      expect(content_type.mime_type).to eq('image/webp')
    end

    it 'detects MP4 videos' do
      content_type = described_class.from_filename('video.mp4')
      expect(content_type.mime_type).to eq('video/mp4')
    end

    it 'detects WebM videos' do
      content_type = described_class.from_filename('video.webm')
      expect(content_type.mime_type).to eq('video/webm')
    end

    it 'detects MOV videos' do
      content_type = described_class.from_filename('video.mov')
      expect(content_type.mime_type).to eq('video/quicktime')
    end

    it 'detects MP3 audio' do
      content_type = described_class.from_filename('audio.mp3')
      expect(content_type.mime_type).to eq('audio/mpeg')
    end

    it 'detects WAV audio' do
      content_type = described_class.from_filename('audio.wav')
      expect(content_type.mime_type).to eq('audio/wave')
    end

    it 'detects FLAC audio' do
      content_type = described_class.from_filename('audio.flac')
      expect(content_type.mime_type).to eq('audio/flac')
    end

    it 'handles case-insensitive extensions' do
      content_type = described_class.from_filename('image.JPG')
      expect(content_type.mime_type).to eq('image/jpeg')
    end

    it 'returns default MIME type for unknown extensions' do
      content_type = described_class.from_filename('file.unknown')
      expect(content_type.mime_type).to eq('application/octet-stream')
    end

    it 'returns default MIME type for blank filename' do
      content_type = described_class.from_filename('')
      expect(content_type.mime_type).to eq('application/octet-stream')
    end

    it 'returns default MIME type for nil filename' do
      content_type = described_class.from_filename(nil)
      expect(content_type.mime_type).to eq('application/octet-stream')
    end
  end

  describe '.from_mime_type' do
    it 'creates ContentType from MIME type' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type.mime_type).to eq('image/jpeg')
      expect(content_type.filename).to eq('')
    end
  end

  describe '#image?' do
    it 'returns true for image MIME types' do
      image_types = %w[image/jpeg image/png image/gif image/webp image/heic image/heif image/avif]
      image_types.each do |mime_type|
        content_type = described_class.from_mime_type(mime_type)
        expect(content_type).to be_image
      end
    end

    it 'returns false for non-image MIME types' do
      content_type = described_class.from_mime_type('video/mp4')
      expect(content_type).not_to be_image
    end
  end

  describe '#video?' do
    it 'returns true for video MIME types' do
      video_types = %w[video/mp4 video/webm video/quicktime video/ogg]
      video_types.each do |mime_type|
        content_type = described_class.from_mime_type(mime_type)
        expect(content_type).to be_video
      end
    end

    it 'returns false for non-video MIME types' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type).not_to be_video
    end
  end

  describe '#audio?' do
    it 'returns true for audio MIME types' do
      audio_types = %w[
        audio/mpeg audio/mp3 audio/ogg audio/vorbis audio/wave audio/wav
        audio/x-wav audio/x-pn-wave audio/flac audio/opus audio/webm audio/mp4
      ]
      audio_types.each do |mime_type|
        content_type = described_class.from_mime_type(mime_type)
        expect(content_type).to be_audio
      end
    end

    it 'returns false for non-audio MIME types' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type).not_to be_audio
    end
  end

  describe '#supported?' do
    it 'returns true for supported MIME types' do
      supported_types = %w[image/jpeg video/mp4 audio/mpeg]
      supported_types.each do |mime_type|
        content_type = described_class.from_mime_type(mime_type)
        expect(content_type).to be_supported
      end
    end

    it 'returns false for unsupported MIME types' do
      content_type = described_class.from_mime_type('application/octet-stream')
      expect(content_type).not_to be_supported
    end
  end

  describe '#to_s' do
    it 'returns the MIME type' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type.to_s).to eq('image/jpeg')
    end
  end

  describe '#==' do
    it 'returns true for same MIME type' do
      content_type1 = described_class.from_mime_type('image/jpeg')
      content_type2 = described_class.from_mime_type('image/jpeg')
      expect(content_type1).to eq(content_type2)
    end

    it 'returns false for different MIME types' do
      content_type1 = described_class.from_mime_type('image/jpeg')
      content_type2 = described_class.from_mime_type('image/png')
      expect(content_type1).not_to eq(content_type2)
    end

    it 'returns false for objects of other classes' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type).not_to eq('image/jpeg')
    end
  end

  describe 'class methods' do
    describe '.supported_mime_types' do
      it 'returns all supported MIME types' do
        supported_types = described_class.supported_mime_types
        expect(supported_types).to include('image/jpeg', 'video/mp4', 'audio/mpeg')
      end
    end

    describe '.supported_image_types' do
      it 'returns supported image MIME types' do
        image_types = described_class.supported_image_types
        expect(image_types).to include('image/jpeg', 'image/png', 'image/gif')
        expect(image_types).not_to include('video/mp4')
      end
    end

    describe '.supported_video_types' do
      it 'returns supported video MIME types' do
        video_types = described_class.supported_video_types
        expect(video_types).to include('video/mp4', 'video/webm')
        expect(video_types).not_to include('image/jpeg')
      end
    end

    describe '.supported_audio_types' do
      it 'returns supported audio MIME types' do
        audio_types = described_class.supported_audio_types
        expect(audio_types).to include('audio/mpeg', 'audio/wav')
        expect(audio_types).not_to include('image/jpeg')
      end
    end
  end

  describe 'immutability' do
    it 'is immutable' do
      content_type = described_class.from_mime_type('image/jpeg')
      expect(content_type).to be_frozen
    end
  end
end
