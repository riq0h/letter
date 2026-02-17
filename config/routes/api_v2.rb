# frozen_string_literal: true

# Mastodon API v2
Rails.application.routes.draw do
  namespace :api do
    namespace :v2 do
      # 検索機能
      get '/search', to: 'search#index'

      # インスタンス (v2)
      get '/instance', to: 'instance#show'

      # サジェスト (v2)
      get '/suggestions', to: 'suggestions#index'

      # トレンド (v2)
      get '/trends/tags', to: 'trends#tags'
      get '/trends/statuses', to: 'trends#statuses'
      get '/trends/links', to: 'trends#links'

      # 通知 (v2) - グループ化通知
      get '/notifications', to: 'notifications#index'
      get '/notifications/unread_count', to: 'notifications#unread_count'
      post '/notifications/clear', to: 'notifications#clear'
      get '/notifications/:group_key', to: 'notifications#show'
      post '/notifications/:group_key/dismiss', to: 'notifications#dismiss'

      # フィルター (v2)
      resources :filters

      # メディア (v2)
      resources :media, only: [:create]
    end
  end
end
