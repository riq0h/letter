# frozen_string_literal: true

# 管理・設定関連ルート
Rails.application.routes.draw do
  # 設定
  get '/config', to: 'config#show', as: :config
  patch '/config', to: 'config#update'
  
  # カスタム絵文字管理
  get '/config/custom_emojis', to: 'config#custom_emojis', as: :config_custom_emojis
  get '/config/custom_emojis/new', to: 'config#new_custom_emoji', as: :new_config_custom_emoji
  post '/config/custom_emojis', to: 'config#create_custom_emoji'
  get '/config/custom_emojis/:id/edit', to: 'config#edit_custom_emoji', as: :edit_config_custom_emoji
  patch '/config/custom_emojis/:id', to: 'config#update_custom_emoji', as: :config_custom_emoji
  delete '/config/custom_emojis/:id', to: 'config#destroy_custom_emoji'
  patch '/config/custom_emojis/:id/enable', to: 'config#enable_custom_emoji', as: :enable_config_custom_emoji
  patch '/config/custom_emojis/:id/disable', to: 'config#disable_custom_emoji', as: :disable_config_custom_emoji
  post '/config/custom_emojis/bulk_action', to: 'config#bulk_action_custom_emojis', as: :bulk_action_config_custom_emojis
  post '/config/custom_emojis/copy_remote', to: 'config#copy_remote_emojis', as: :copy_remote_config_custom_emojis
  post '/config/custom_emojis/discover_remote', to: 'config#discover_remote_emojis', as: :discover_remote_config_custom_emojis
  
  # リレー管理ルート
  get '/config/relays', to: 'config#relays', as: :config_relays
  post '/config/relays', to: 'config#create_relay'
  patch '/config/relays/:id', to: 'config#update_relay', as: :config_relay
  delete '/config/relays/:id', to: 'config#destroy_relay'
end