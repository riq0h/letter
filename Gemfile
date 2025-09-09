# frozen_string_literal: true

# Gemfile
source 'https://rubygems.org'

ruby '3.4.1'

# Rails 8
gem 'bootsnap', require: false
gem 'dotenv-rails'
gem 'image_processing', '~> 1.2'
gem 'importmap-rails'
gem 'ostruct'
gem 'puma', '>= 5.0'
gem 'rails', '~> 8.0.0'
# gem 'sassc-rails'  # TailwindCSS v4との互換性問題のため無効化
gem 'propshaft'
gem 'sqlite3', '>= 2.1'
gem 'stimulus-rails'
gem 'tailwindcss-rails'
gem 'turbo-rails'

# ActivityPub & 連合機能
gem 'addressable'
gem 'httparty'
gem 'json-ld'
gem 'nokogiri'
gem 'rsa'

# 認証
gem 'bcrypt', '~> 3.1.7'
gem 'doorkeeper', '~> 5.7'
gem 'jwt'
gem 'rack-cors'

# Solid
# gem 'solid_cable'
gem 'solid_cache'
gem 'solid_queue'

# プッシュ通知
gem 'web-push'

# ユーティリティ
gem 'active_model_serializers'
gem 'aws-sdk-s3', require: false
gem 'blurhash'
gem 'foreman'
gem 'kaminari'
gem 'marcel'
gem 'mini_magick'
gem 'nanoid'

group :development, :test do
  gem 'brakeman'
  gem 'debug', platforms: %i[mri windows]
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'pry-rails'
  gem 'rspec-rails'
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'shoulda-matchers'
end

group :development do
  gem 'annotate'
  gem 'bullet'
  gem 'listen', '~> 3.3'
  gem 'spring'
  gem 'web-console'
end
