require_relative 'boot'

# 環境変数の明示的な読み込み
if File.exist?(File.expand_path('../.env', __dir__))
  require 'dotenv'
  Dotenv.load(File.expand_path('../.env', __dir__))
end

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
# require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Letter
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Asia/Tokyo"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil
    config.active_record.schema_format = :sql
    
    # インスタンス設定のデフォルト値
    config.instance_name = "letter"
    config.instance_description = "General Letter Publication System based on ActivityPub"
    config.instance_contact_email = ""
    config.instance_maintainer = ""
    config.blog_footer = "General Letter Publication System based on ActivityPub"
    
    # カスタムエラーページを使用
    # config.exceptions_app = self.routes
    
    # アプリケーション名を設定
    config.application_name = "letter"
  end
end
