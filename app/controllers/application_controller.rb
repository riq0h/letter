# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  protect_from_forgery with: :exception, unless: -> { activitypub_request? || api_request? }
  before_action :set_locale

  # 認証ヘルパーメソッドをビューでも使用可能にする
  helper_method :current_user, :user_signed_in?, :blog_title, :blog_footer

  private

  def activitypub_request?
    request.content_type == 'application/activity+json' ||
      request.content_type == 'application/ld+json' ||
      request.headers['Accept']&.include?('application/activity+json') ||
      request.headers['Accept']&.include?('application/ld+json')
  end

  def api_request?
    request.path.start_with?('/api/')
  end

  # 現在ログイン中のユーザを取得
  def current_user
    return nil unless session[:current_user_id]

    @current_user ||= Actor.find_by(id: session[:current_user_id], local: true)
  end

  # ログイン状態判定
  def user_signed_in?
    current_user.present?
  end

  def blog_title
    stored_config = load_instance_config
    stored_config['instance_name'] || Rails.application.config.instance_name || 'letter'
  end

  def blog_footer
    stored_config = load_instance_config
    stored_config['blog_footer'] || Rails.application.config.blog_footer || 'General Letter Publication System based on ActivityPub'
  end

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

  # 認証必須ページの保護
  def authenticate_user!
    return if user_signed_in?

    store_return_location
    redirect_to login_path, alert: I18n.t('auth.login_required')
  end

  # リダイレクト後の戻り先を保存
  def store_return_location
    session[:return_to] = request.fullpath if request.get? && !request.xhr?
  end

  def set_locale
    I18n.locale = extract_locale || I18n.default_locale
  end

  def extract_locale
    parsed_locale = request.env['HTTP_ACCEPT_LANGUAGE']&.scan(/^[a-z]{2}/)&.first
    I18n.available_locales.map(&:to_s).include?(parsed_locale) ? parsed_locale : nil
  end

  def activitypub_content_type
    'application/activity+json; charset=utf-8'
  end

  # 一貫したbase_url取得（環境変数制御下）
  def activitypub_base_url
    Rails.application.config.activitypub.base_url
  end
end
