# frozen_string_literal: true

module ApIdGeneration
  extend ActiveSupport::Concern

  included do
    before_validation :set_ap_id, on: :create
  end

  # モジュールメソッドとしてどこからでも呼べるようにする
  def self.generate_ap_id
    snowflake_id = Letter::Snowflake.generate
    "#{Rails.application.config.activitypub.base_url}/#{snowflake_id}"
  end

  private

  def set_ap_id
    return if ap_id.present?

    self.ap_id = ApIdGeneration.generate_ap_id
  end
end
