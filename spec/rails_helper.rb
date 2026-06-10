# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = ["#{Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot設定
  config.include FactoryBot::Syntax::Methods

  # テスト用のヘルパー設定
  config.before(:each, type: :controller) do
    @routes = Rails.application.routes
  end

  # Doorkeeper認証のテストヘルパー
  config.before(:each, type: :controller) do
    request.env['HTTP_AUTHORIZATION'] = nil
  end

  # ActivityPubテスト用の設定
  config.before(:suite) do
    # テスト用の設定を確実に読み込む
    Rails.application.config.activitypub.domain = 'test.example.com'
    Rails.application.config.activitypub.base_url = 'https://test.example.com'

    # レイアウトが参照するビルド済みアセットのプレースホルダを用意する
    # （tailwindcss:build未実行の環境でもレイアウトを描画するspecが落ちないように）
    builds_dir = Rails.root.join('app/assets/builds')
    FileUtils.mkdir_p(builds_dir)
    FileUtils.touch(builds_dir.join('tailwind.css'))
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
