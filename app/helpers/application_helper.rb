# frozen_string_literal: true

module ApplicationHelper
  include StatusSerializer

  def background_color
    stored_config = load_instance_config
    stored_config['background_color'] || '#fdfbfb'
  end

  private

  def load_instance_config
    config_file = Rails.root.join('config', 'instance_config.yml')
    if File.exist?(config_file)
      YAML.safe_load_file(config_file) || {}
    else
      {}
    end
  rescue StandardError => e
    Rails.logger.error "Failed to load config: #{e.message}"
    {}
  end
end
