Rails.application.configure do
  # ActivityPub設定
  config.activitypub = ActiveSupport::OrderedOptions.new

  # ドメイン設定
  config.activitypub.domain = ENV.fetch('ACTIVITYPUB_DOMAIN') do
    if Rails.env.development?
      'localhost:3000'
    elsif Rails.env.test?
      'test.example'
    else
      raise 'ACTIVITYPUB_DOMAIN environment variable is required in production'
    end
  end

  # プロトコル設定
  config.activitypub.protocol = ENV.fetch('ACTIVITYPUB_PROTOCOL') do
    if Rails.env.development?
      'https'
    else
      'https'
    end
  end

  # ベースURL構築
  config.activitypub.base_url = "#{config.activitypub.protocol}://#{config.activitypub.domain}"

  # ActivityPub標準URL
  config.activitypub.context_url = 'https://www.w3.org/ns/activitystreams'
  config.activitypub.public_collection_url = 'https://www.w3.org/ns/activitystreams#Public'

  # 投稿制限
  config.activitypub.character_limit = 9999
  config.activitypub.max_accounts = 2

  # メディア制限
  config.activitypub.max_image_size = 50.megabytes
  config.activitypub.max_video_size = 500.megabytes
  config.activitypub.max_audio_size = 250.megabytes
  config.activitypub.max_document_size = 100.megabytes

  # フェデレーション設定
  config.activitypub.federation_enabled = ENV.fetch('FEDERATION_ENABLED', 'true') == 'true'
  config.activitypub.http_timeout = 10.seconds
  config.activitypub.max_redirects = 3

  # セキュリティ設定
  config.activitypub.require_http_signatures = Rails.env.production?
  config.activitypub.signature_algorithm = 'rsa-sha256'

  # インスタンス情報
  instance_config = YAML.load_file(Rails.root.join('config/instance_config.yml'))
  config.instance_name = instance_config['instance_name']
  config.instance_description = instance_config['instance_description']
  config.instance_contact_email = ENV.fetch('CONTACT_EMAIL', 'admin@localhost')
  config.instance_maintainer = ENV.fetch('MAINTAINER_NAME', 'letter Administrator')

  # UI設定
  config.activitypub.default_locale = 'ja'
  config.activitypub.supported_locales = %w[ja en]

  # ログ設定
  config.activitypub.log_level = Rails.env.production? ? :info : :debug
end

# バリデーション
Rails.application.config.after_initialize do
  domain = Rails.application.config.activitypub.domain
  protocol = Rails.application.config.activitypub.protocol

  if Rails.env.production?
    unless domain.present? && domain.include?('.')
      Rails.logger.error "Invalid ActivityPub domain: #{domain}"
      raise 'ActivityPub domain must be a valid domain name in production'
    end

    if domain.include?('localhost')
      Rails.logger.error 'localhost is not allowed in production'
      raise 'ActivityPub domain cannot be localhost in production'
    end
  end

  # URL設定を確実に適用
  Rails.application.routes.default_url_options = {
    host: domain,
    protocol: protocol
  }

  Rails.logger.info "ActivityPub configured for domain: #{domain}"
end
