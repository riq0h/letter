# frozen_string_literal: true

module MediaSerializer
  extend ActiveSupport::Concern

  private

  def serialized_media_attachments(status)
    # 防御的プログラミング: 常に配列を返し、nullは返さない
    return [] unless status.respond_to?(:media_attachments)
    return [] if status.media_attachments.nil?

    attachments = status.media_attachments.filter_map do |media|
      serialize_single_media_attachment(media)
    end

    # 常に配列であることを保証
    attachments.is_a?(Array) ? attachments : []
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize media attachments for status #{status.id}: #{e.message}"
    Rails.logger.warn "Backtrace: #{e.backtrace.first(3).join(', ')}"
    [] # エラー時は常に空配列を返す
  end

  # 単一メディアのシリアライズ（MediaController用公開メソッド）
  def serialized_media_attachment(media)
    serialize_single_media_attachment(media)
  end

  def serialize_single_media_attachment(media)
    # メディアの存在をバリデート
    return nil unless media

    media_url = begin
      media.url
    rescue StandardError
      nil
    end
    preview_url = begin
      media.preview_url
    rescue StandardError
      nil
    end

    {
      id: media.id.to_s,
      type: media.media_type.to_s,
      url: media_url || media.remote_url || '',
      preview_url: preview_url || (media.image? ? (media_url || media.remote_url || '') : ''),
      remote_url: media.remote_url.to_s,
      meta: build_media_meta(media),
      description: media.description.to_s,
      blurhash: media.blurhash.to_s
    }
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize media attachment #{media&.id}: #{e.message}"
    nil
  end

  def build_media_meta(media)
    original = build_original_meta(media)
    small = build_small_meta(media)
    focus = extract_focus_point(media)

    # ディメンション情報もfocusもない場合はnilを返す
    return nil if original.empty? && small.empty? && focus.nil?

    meta = { original: original, small: small }
    meta[:focus] = focus if focus
    meta
  end

  def build_original_meta(media)
    return {} unless media.width && media.height

    {
      width: media.width,
      height: media.height,
      size: "#{media.width}x#{media.height}",
      aspect: media.height.zero? ? 0 : (media.width.to_f / media.height).round(2)
    }
  end

  def build_small_meta(media)
    return {} unless media.width && media.height

    if media.width > 400
      small_height = media.width.zero? ? 0 : (media.height * 400 / media.width).round
      {
        width: 400,
        height: small_height,
        size: "400x#{small_height}",
        aspect: media.height.zero? ? 0 : (media.width.to_f / media.height).round(2)
      }
    else
      build_original_meta(media)
    end
  end

  def extract_focus_point(media)
    return nil if media.metadata.blank?

    parsed = media.metadata.is_a?(String) ? JSON.parse(media.metadata) : media.metadata
    focus_x = parsed['focus_x'] || parsed['focusX']
    focus_y = parsed['focus_y'] || parsed['focusY']

    return nil unless focus_x && focus_y

    { x: focus_x.to_f, y: focus_y.to_f }
  rescue JSON::ParserError
    nil
  end
end
