# frozen_string_literal: true

# インスタンス設定をデータベースで管理するモデル
class InstanceConfig < ApplicationRecord
  # 設定のキー制限（セキュリティ対策）
  ALLOWED_KEYS = %w[
    instance_name
    instance_description
    instance_contact_email
    instance_maintainer
    blog_footer
    background_color
  ].freeze

  validates :config_key, presence: true, inclusion: { in: ALLOWED_KEYS }
  validates :value, presence: true
  validates :config_key, uniqueness: true

  # 設定値を取得するクラスメソッド
  def self.get(key)
    Rails.cache.fetch("instance_config:#{key}", expires_in: 1.hour) do
      find_by(config_key: key)&.value
    end
  end

  # 設定値を設定するクラスメソッド
  def self.set(key, value)
    return false unless ALLOWED_KEYS.include?(key.to_s)

    config = find_or_initialize_by(config_key: key.to_s)
    config.value = value.to_s

    if config.save
      Rails.cache.delete("instance_config:#{key}")
      true
    else
      false
    end
  end

  # 全設定をハッシュで取得
  def self.all_as_hash
    Rails.cache.fetch('instance_config:all', expires_in: 1.hour) do
      pluck(:config_key, :value).to_h
    end
  end

  # 複数設定を一括更新
  def self.bulk_update(config_hash)
    transaction do
      config_hash.each do |key, value|
        next unless ALLOWED_KEYS.include?(key.to_s)

        set(key, value)
      end
    end

    # キャッシュクリア
    clear_all_cache
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  # キャッシュクリア
  def self.clear_all_cache
    ALLOWED_KEYS.each do |key|
      Rails.cache.delete("instance_config:#{key}")
    end
    Rails.cache.delete('instance_config:all')
  end

  # 外部データソースからの設定移行
  def self.import_from_hash(data_hash)
    return false unless data_hash.is_a?(Hash)

    begin
      transaction do
        data_hash.each do |key, value|
          next unless ALLOWED_KEYS.include?(key.to_s)

          set(key, value)
        end
      end

      Rails.logger.info 'Successfully imported instance configuration'
      true
    rescue StandardError => e
      Rails.logger.error "Failed to import instance config: #{e.message}"
      false
    end
  end

  # User-Agent configuration methods
  def self.user_agent(context = :default)
    base_agent = 'letter'

    case context
    when :activitypub
      "#{base_agent} (ActivityPub)"
    when :web
      "Mozilla/5.0 (compatible; #{base_agent}; +https://github.com/riq0h/letter)"
    when :import
      "#{base_agent} (Mastodon Import)"
    else
      base_agent
    end
  end

  # Application constants
  APPLICATION_NAME = 'letter'
  REPOSITORY_URL = 'https://github.com/riq0h/letter'
end
