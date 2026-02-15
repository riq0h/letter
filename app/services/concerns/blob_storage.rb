# frozen_string_literal: true

# S3/ローカルストレージ分岐のblob作成ロジックを共通化するconcern
module BlobStorage
  extend ActiveSupport::Concern

  private

  # S3有効時はカスタムキー付きでR2にアップロード、無効時はローカルストレージ
  # @param io [IO] アップロードするファイルのIO
  # @param filename [String] ファイル名
  # @param content_type [String] Content-Type
  # @param folder [String] S3上のフォルダプレフィックス (例: "img", "avatar", "cache")
  # @return [ActiveStorage::Blob]
  def create_storage_blob(io:, filename:, content_type:, folder:)
    if ENV['S3_ENABLED'] == 'true'
      custom_key = "#{folder}/#{SecureRandom.hex(16)}"
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
    else
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type
      )
    end
  end
end
