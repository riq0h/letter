# frozen_string_literal: true

module ActivityBuilders
  class AttachmentBuilder
    def initialize(object)
      @object = object
    end

    def build
      @object.media_attachments.map do |attachment|
        data = {
          'type' => 'Document',
          'mediaType' => attachment.content_type,
          'url' => attachment.url,
          'name' => attachment.description || attachment.file_name,
          'width' => attachment.width,
          'height' => attachment.height,
          'blurhash' => attachment.blurhash
        }

        # focalPoint（注目点座標）があれば追加
        focal_point = extract_focal_point(attachment)
        data['focalPoint'] = focal_point if focal_point

        data.compact
      end
    end

    private

    def extract_focal_point(attachment)
      return nil if attachment.metadata.blank?

      parsed = attachment.metadata.is_a?(String) ? JSON.parse(attachment.metadata) : attachment.metadata
      focus_x = parsed['focus_x'] || parsed['focusX']
      focus_y = parsed['focus_y'] || parsed['focusY']

      return nil unless focus_x && focus_y

      [focus_x.to_f, focus_y.to_f]
    rescue JSON::ParserError
      nil
    end
  end
end
