# frozen_string_literal: true

class CustomEmoji < ApplicationRecord
  include RemoteLocalHelper

  # ショートコード検出用正規表現（EmojiFormatterから参照）
  SHORTCODE_RE_FRAGMENT = '[a-zA-Z0-9_-]{2,}'
  SCAN_RE = /:(#{SHORTCODE_RE_FRAGMENT}):/o

  # ショートコード長の上限。Misskey等は長いショートコード(35文字超)を使うため
  # 従来の30では正当なリモート絵文字が保存できなかった。ローカル/リモートで
  # 上限を分けると、リモート絵文字をローカルにコピーする際(RemoteEmojiCopyService)に
  # ローカル上限で弾かれてしまうため、単一の上限に統一する。
  SHORTCODE_MIN_LENGTH = 2
  SHORTCODE_MAX_LENGTH = 100

  # バリデーション
  validates :shortcode, presence: true, format: { with: /\A[a-zA-Z0-9_-]+\z/ }
  validates :shortcode, uniqueness: { scope: :domain, case_sensitive: false }
  validates :image_url, presence: true, if: -> { remote? }

  # スコープ
  scope :local, -> { where(domain: nil) }
  scope :remote, -> { where.not(domain: nil) }
  scope :enabled, -> { where(disabled: false) }
  scope :visible, -> { where(visible_in_picker: true) }
  scope :alphabetical, -> { order(:shortcode) }
  scope :by_domain, ->(domain) { where(domain: domain) }

  # ファイルアップロード
  has_one_attached :image

  # カスタムアップロードメソッド（フォルダ構造対応）
  # folder: 自前アップロード/ローカルコピーは 'emoji'、リモート画像のキャッシュは 'cache'
  def attach_image_with_folder(io:, filename:, content_type:, folder: 'emoji')
    if ENV['S3_ENABLED'] == 'true'
      # S3の場合、キーに folder/ プレフィックスを付ける
      custom_key = "#{folder}/#{SecureRandom.hex(16)}"
      blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: content_type,
        service_name: :cloudflare_r2,
        key: custom_key
      )
      image.attach(blob)
    else
      # ローカルの場合は通常通り
      image.attach(io: io, filename: filename, content_type: content_type)
    end
  end

  # バリデーション
  validate :shortcode_length
  validate :image_presence

  # コールバック
  before_validation :normalize_shortcode
  after_create :update_cache
  after_update :update_cache
  after_destroy :update_cache

  # メソッド
  def local?
    domain.nil?
  end

  def url
    # ローカル絵文字も、ローカルキャッシュ済みのリモート絵文字も添付(R2)から配信する。
    # 未キャッシュのリモート絵文字のみ直リンクし、表示契機でローカル取り込みを予約する。
    # (直リンクはリモートCDNのホットリンク保護=Referer拒否で壊れることがあるため)
    if image.attached?
      # Cloudflare R2のカスタムドメインを使用
      if ENV['S3_ENABLED'] == 'true' && ENV['S3_ALIAS_HOST'].present?
        "https://#{ENV.fetch('S3_ALIAS_HOST', nil)}/#{image.blob.key}"
      else
        Rails.application.routes.url_helpers.url_for(image)
      end
    elsif remote?
      self[:image_url]
    end
  end

  def image_url
    url
  end

  def static_url
    # ローカル絵文字の場合は同じURL、リモートの場合は静的版のURLがあれば使用
    image_url
  end

  # Mastodon API準拠のJSON表現
  def to_activitypub
    # 表示契機。未キャッシュのリモート絵文字ならローカル取り込み(R2)を予約する
    request_remote_image_cache
    {
      id: id,
      shortcode: shortcode,
      url: image_url,
      static_url: static_url,
      visible_in_picker: visible_in_picker,
      category: category_id
    }
  end

  # 表示時に呼ばれ、未キャッシュのリモート絵文字画像をR2へ取り込むジョブを予約する。
  # (url自体は副作用を持たせない。image_presenceバリデーション等からも呼ばれるため)
  # 12時間に1回だけ(unless_exist)＆同一インスタンス1回だけに制限。
  def request_remote_image_cache
    return if @remote_image_cache_requested
    return unless remote? && !image.attached?

    @remote_image_cache_requested = true
    return if self[:image_url].blank? || !persisted?
    return unless Rails.cache.write("emoji_img_cache:#{id}", true, expires_in: 12.hours, unless_exist: true)

    CacheRemoteEmojiJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.debug { "Remote emoji cache enqueue skipped for #{id}: #{e.message}" }
  end

  # ActivityPub表現
  def to_ap
    {
      id: id,
      type: 'Emoji',
      name: ":#{shortcode}:",
      icon: {
        type: 'Image',
        url: image_url
      }
    }
  end

  private

  def normalize_shortcode
    self.shortcode = shortcode.to_s.downcase.strip
  end

  def shortcode_length
    return if shortcode.blank?
    return if shortcode.length.between?(SHORTCODE_MIN_LENGTH, SHORTCODE_MAX_LENGTH)

    errors.add(:shortcode, "must be between #{SHORTCODE_MIN_LENGTH} and #{SHORTCODE_MAX_LENGTH} characters")
  end

  def image_presence
    return if remote? && image_url.present?
    return if local? && image.attached?

    errors.add(:image, 'must be present')
  end

  def update_cache
    Rails.cache.delete('custom_emojis')
    Rails.cache.delete("custom_emojis:#{domain}")
    Rails.cache.delete('api:v1:custom_emojis')
  end

  class << self
    def cached
      Rails.cache.fetch('custom_emojis', expires_in: 1.hour) do
        enabled.includes(:image_attachment).to_a
      end
    end

    def search(query)
      return none if query.blank?

      where('shortcode LIKE ?', "%#{sanitize_sql_like(query)}%")
        .enabled
        .alphabetical
        .limit(20)
    end

    def by_shortcodes(shortcodes)
      where(shortcode: shortcodes, domain: nil)
        .enabled
    end

    def from_text(text)
      return {} if text.blank?

      shortcodes = text.scan(SCAN_RE).flatten.uniq

      return {} if shortcodes.empty?

      emojis = by_shortcodes(shortcodes)
      emojis.index_by(&:shortcode)
    end
  end
end
