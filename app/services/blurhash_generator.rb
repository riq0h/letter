# frozen_string_literal: true

require 'blurhash'

# 画像からblurhash(読み込み中に表示するぼかし)を計算する。成分数はMastodonと同じ4x4
module BlurhashGenerator
  # 値が無いメディアに入れる単色の代替値
  PLACEHOLDER = 'L0Eyb[0000000000000000000000'
  # blurhashは小さい画像で十分なので、この大きさに縮小してから計算する
  MAX_SIZE = 128

  module_function

  # 画像ファイルから計算する。計算できなければnil
  def from_file(path)
    require 'vips'
    from_vips(Vips::Image.thumbnail(path.to_s, MAX_SIZE, height: MAX_SIZE))
  rescue StandardError => e
    Rails.logger.warn "Failed to generate blurhash from file: #{e.message}"
    nil
  end

  # 画像データから計算する。計算できなければnil
  def from_buffer(data)
    require 'vips'
    from_vips(Vips::Image.thumbnail_buffer(data, MAX_SIZE, height: MAX_SIZE))
  rescue StandardError => e
    Rails.logger.warn "Failed to generate blurhash from buffer: #{e.message}"
    nil
  end

  # libvipsの画像から計算する。失敗時は例外を投げる
  def from_vips(image)
    scale = [MAX_SIZE.to_f / image.width, MAX_SIZE.to_f / image.height].min
    image = image.resize(scale) if scale < 1

    # RGBの3チャンネルにそろえる(アルファチャンネルは除く)
    image = image.colourspace('srgb') unless image.interpretation == :srgb
    image = image.extract_band(0, n: 3) if image.bands > 3

    pixels = image.write_to_memory.unpack('C*')
    Blurhash.encode(image.width, image.height, pixels, x_comp: 4, y_comp: 4)
  end
end
