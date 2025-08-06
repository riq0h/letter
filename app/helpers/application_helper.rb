# frozen_string_literal: true

module ApplicationHelper
  include StatusSerializer

  def background_color
    stored_config = load_instance_config
    stored_config['background_color'] || '#fdfbfb'
  end

  private

  def load_instance_config
    InstanceConfig.all_as_hash
  rescue StandardError => e
    Rails.logger.error "Failed to load config from database: #{e.message}"
    {}
  end
end
