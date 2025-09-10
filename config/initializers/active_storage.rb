# frozen_string_literal: true

# Cloudflare R2 compatibility settings
if ENV['S3_ENABLED'] == 'true'
  # R2 doesn't support MD5 checksums in the same way as S3
  Rails.application.config.active_storage.checksum_algorithm = nil
end

# 画像の自動リサイズを無効化
Rails.application.config.active_storage.variant_processor = :vips
Rails.application.config.active_storage.analyzers = []
