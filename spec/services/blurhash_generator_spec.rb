# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe BlurhashGenerator do
  # 左が赤・右が青の画像(単色ではないので代替値と区別できる)
  def two_colour_image(width: 64, height: 32)
    half = width / 2
    red = Vips::Image.black(half, height).new_from_image([220, 30, 30])
    blue = Vips::Image.black(half, height).new_from_image([30, 30, 220])
    red.join(blue, :horizontal).copy(interpretation: :srgb)
  end

  def expect_real_blurhash(blurhash)
    expect(blurhash).to be_present
    expect(blurhash).not_to eq(described_class::PLACEHOLDER)
    expect(Blurhash.components(blurhash)).to eq([4, 4])
  end

  describe '.from_buffer' do
    it 'computes a blurhash from encoded image data' do
      expect_real_blurhash(described_class.from_buffer(two_colour_image.write_to_buffer('.png')))
    end

    it 'handles large images, alpha channels and greyscale images' do
      large = two_colour_image(width: 2000, height: 1200)
      with_alpha = two_colour_image.bandjoin(255)
      grey = two_colour_image.colourspace('b-w')

      [large, with_alpha, grey].each do |image|
        expect_real_blurhash(described_class.from_buffer(image.write_to_buffer('.png')))
      end
    end

    it 'returns nil for data that is not an image' do
      expect(described_class.from_buffer('not an image')).to be_nil
    end
  end

  describe '.from_file' do
    it 'computes a blurhash from an image file regardless of its extension' do
      Tempfile.create(['remote_media', '.bin']) do |file|
        file.binmode
        file.write(two_colour_image.write_to_buffer('.jpg'))
        file.flush

        expect_real_blurhash(described_class.from_file(file.path))
      end
    end

    it 'returns nil for a missing file' do
      expect(described_class.from_file('/nonexistent/image.png')).to be_nil
    end
  end
end
