# frozen_string_literal: true

require 'open3'

# 動画からサムネイル用のコマを1枚(JPEG)切り出す。
# 先頭(0秒)のコマはうまく生成されないことがあるため、少し進めた位置
# (1秒。2秒未満の動画は長さの半分)から取る
module VideoFrameExtractor
  PREFERRED_OFFSET = 1.0

  module_function

  # 切り出せたらtrue。inputはファイルパスまたはURL。durationが無ければffprobeで調べる
  def extract(input, output_path, duration: nil)
    duration ||= probe_duration(input)
    offset = frame_offset(duration)
    return true if run_ffmpeg(input, output_path, offset)

    # 長さが分からず末尾を越えた場合などは、先頭のコマで妥協する
    offset.positive? && run_ffmpeg(input, output_path, 0)
  end

  def frame_offset(duration)
    return PREFERRED_OFFSET unless duration&.positive?

    [PREFERRED_OFFSET, duration / 2.0].min.round(3)
  end

  def probe_duration(input)
    stdout, _, status = Open3.capture3('ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                                       '-of', 'csv=p=0', input)
    return nil unless status.success?

    Float(stdout.strip, exception: false)
  end

  def run_ffmpeg(input, output_path, offset)
    cmd = ['ffmpeg', '-v', 'error']
    cmd += ['-ss', format('%.3f', offset)] if offset.positive?
    cmd += ['-i', input, '-frames:v', '1', '-q:v', '2', '-y', output_path]
    _, stderr, status = Open3.capture3(*cmd)

    extracted = status.success? && File.size?(output_path).to_i.positive?
    Rails.logger.warn "Video frame extraction at #{offset}s failed: #{stderr.to_s.lines.last(2).join.strip}" unless extracted
    extracted
  end
end
