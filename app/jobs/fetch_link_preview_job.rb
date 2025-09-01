# frozen_string_literal: true

# URLからOGP情報を取得してリンクプレビューカードを生成するジョブ
# Solid Cableを使ったリアルタイム更新対応
class FetchLinkPreviewJob < ApplicationJob
  queue_as :default

  # リトライ設定: ネットワークエラーに対応
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # タイムアウト設定: 長時間のURL取得を防ぐ
  discard_on Net::TimeoutError, Net::ReadTimeout, Net::OpenTimeout

  def perform(url, activity_pub_object_id = nil)
    Rails.logger.info "🔗 Fetching link preview for: #{url}"

    return unless valid_url?(url)

    # 既存のプレビューがあるかチェック
    existing_preview = LinkPreview.find_by(url: url)
    if existing_preview&.fresh?
      Rails.logger.debug { "✅ Fresh link preview already exists for: #{url}" }
      return existing_preview
    end

    # リンクプレビューを取得または作成
    preview = LinkPreview.fetch_or_create(url)

    if preview
      Rails.logger.info "✅ Link preview created/updated for: #{url}"

      # 関連するActivityPubObjectの処理完了ログ
      if activity_pub_object_id
        object = ActivityPubObject.find_by(id: activity_pub_object_id)
        Rails.logger.debug { "✅ Link preview processed for object #{object.id}" } if object
      end

      preview
    else
      Rails.logger.warn "⚠️  Failed to create link preview for: #{url}"
      nil
    end
  rescue StandardError => e
    handle_error(e, "Link preview fetch failed for #{url}")
  end

  private

  def valid_url?(url)
    return false if url.blank?

    # 基本的なURL形式チェック
    uri = URI.parse(url)
    return false unless %w[http https].include?(uri.scheme)

    # 危険なドメインやIPアドレスのフィルタリング（セキュリティ）
    return false if dangerous_url?(uri)

    true
  rescue URI::InvalidURIError
    Rails.logger.warn "⚠️  Invalid URL format: #{url}"
    false
  end

  def dangerous_url?(uri)
    # プライベートIPアドレス範囲をブロック
    return true if private_ip?(uri.host)

    # localhost, 127.0.0.1 などをブロック
    return true if %w[localhost 127.0.0.1 0.0.0.0].include?(uri.host)

    false
  rescue StandardError
    true # エラーが発生した場合は安全側に倒す
  end

  def private_ip?(host)
    return false unless host

    # IPアドレス形式かチェック
    ip = IPAddr.new(host)
    ip.private?
  rescue IPAddr::InvalidAddressError
    false # ドメイン名の場合は許可
  end
end
