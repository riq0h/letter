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

  validates :key, presence: true, inclusion: { in: ALLOWED_KEYS }
  validates :value, presence: true
  validates :key, uniqueness: true

  # 設定値を取得するクラスメソッド
  def self.get(key)
    Rails.cache.fetch("instance_config:#{key}", expires_in: 1.hour) do
      find_by(key: key)&.value
    end
  end

  # 設定値を設定するクラスメソッド
  def self.set(key, value)
    return false unless ALLOWED_KEYS.include?(key.to_s)

    config = find_or_initialize_by(key: key.to_s)
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
      pluck(:key, :value).to_h
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
    Rails.cache.delete_matched('instance_config:*')
    true
  rescue ActiveRecord::RecordInvalid
    false
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
end
