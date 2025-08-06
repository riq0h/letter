# frozen_string_literal: true

module ConfigBuilder
  extend ActiveSupport::Concern

  private

  def build_base_config
    stored_config = build_stored_config_hash
    build_instance_config_hash(stored_config).merge(build_activitypub_config)
  end

  def build_stored_config_hash
    InstanceConfig.all_as_hash
  rescue StandardError => e
    Rails.logger.error "Failed to load config from database: #{e.message}"
    {}
  end

  def build_instance_config_hash(stored_config)
    {
      instance_name: get_config_value('instance_name', stored_config),
      instance_description: get_config_value('instance_description', stored_config),
      instance_contact_email: get_config_value('instance_contact_email', stored_config),
      instance_maintainer: get_config_value('instance_maintainer', stored_config),
      accent_color: get_config_value('accent_color', stored_config),
      background_color: get_config_value('background_color', stored_config),
      blog_footer: get_config_value('blog_footer', stored_config)
    }
  end

  def get_config_value(key, stored_config)
    case key
    when 'accent_color'
      stored_config[key] || '#1d4ed8'
    when 'background_color'
      stored_config[key] || '#fdfbfb'
    when 'instance_name'
      stored_config[key] || 'letter'
    when 'instance_description', 'blog_footer'
      stored_config[key] || 'General Letter Publication System based on ActivityPub'
    when 'instance_contact_email'
      stored_config[key] || 'admin@localhost'
    when 'instance_maintainer'
      stored_config[key] || 'letter Administrator'
    else
      stored_config[key]
    end
  end

  def build_activitypub_config
    build_activitypub_settings.merge(build_r2_settings)
  end

  def build_activitypub_settings
    {
      activitypub: {
        base_url: Rails.application.config.activitypub.base_url,
        username: Rails.application.config.activitypub.username,
        ap_id: Rails.application.config.activitypub.ap_id,
        inbox_url: Rails.application.config.activitypub.inbox_url,
        outbox_url: Rails.application.config.activitypub.outbox_url
      }
    }
  end

  def build_r2_settings
    {
      r2: {
        s3_enabled: ENV['S3_ENABLED'] == 'true',
        s3_endpoint: ENV.fetch('S3_ENDPOINT', nil),
        s3_bucket: ENV.fetch('S3_BUCKET', nil),
        r2_access_key_id: ENV.fetch('R2_ACCESS_KEY_ID', nil),
        r2_secret_access_key: ENV.fetch('R2_SECRET_ACCESS_KEY', nil),
        s3_alias_host: ENV.fetch('S3_ALIAS_HOST', nil)
      }
    }
  end
end
