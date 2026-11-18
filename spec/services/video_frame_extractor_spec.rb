# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VideoFrameExtractor do
  describe '.frame_offset' do
    it 'takes the frame at 1 second for videos long enough' do
      expect(described_class.frame_offset(10.0)).to eq(1.0)
      expect(described_class.frame_offset(2.0)).to eq(1.0)
    end

    it 'takes the middle frame for videos shorter than 2 seconds' do
      expect(described_class.frame_offset(0.52)).to eq(0.26)
    end

    it 'falls back to 1 second when the duration is unknown' do
      expect(described_class.frame_offset(nil)).to eq(1.0)
      expect(described_class.frame_offset(0)).to eq(1.0)
    end
  end

  describe '.extract' do
    let(:dir) { Dir.mktmpdir }
    let(:output) { File.join(dir, 'thumb.jpg') }

    before { skip 'ffmpeg not available' unless system('ffmpeg', '-version', out: File::NULL, err: File::NULL) }

    after { FileUtils.remove_entry(dir) }

    def make_video(seconds)
      path = File.join(dir, "video_#{seconds}.mp4")
      system('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', "color=c=red:s=64x48:d=#{seconds}",
             '-pix_fmt', 'yuv420p', '-y', path, exception: true)
      path
    end

    it 'extracts a frame from a video shorter than 1 second' do
      expect(described_class.extract(make_video(0.5), output)).to be(true)
      expect(File.size(output)).to be_positive
    end

    it 'extracts a frame from a longer video' do
      expect(described_class.extract(make_video(3), output)).to be(true)
      expect(File.size(output)).to be_positive
    end

    it 'retries from the start when the given duration overshoots the video' do
      expect(described_class.extract(make_video(0.5), output, duration: 30)).to be(true)
      expect(File.size(output)).to be_positive
    end
  end
end
