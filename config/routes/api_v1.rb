# frozen_string_literal: true

# Mastodon API v1
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # OAuthとアプリ
      post '/apps', to: 'apps#create'
      get '/apps/verify_credentials', to: 'apps#verify_credentials'

      # アカウント
      get '/accounts/verify_credentials', to: 'accounts#verify_credentials'
      patch '/accounts/update_credentials', to: 'accounts#update_credentials'
      get '/accounts/relationships', to: 'accounts#relationships'
      get '/accounts/search', to: 'accounts#search'
      get '/accounts/lookup', to: 'accounts#lookup'
      get '/accounts/:id', to: 'accounts#show'
      get '/accounts/:id/statuses', to: 'accounts#statuses'
      get '/accounts/:id/followers', to: 'accounts#followers'
      get '/accounts/:id/following', to: 'accounts#following'
      get '/accounts/:id/featured_tags', to: 'accounts#featured_tags'
      post '/accounts/:id/follow', to: 'accounts#follow'
      post '/accounts/:id/unfollow', to: 'accounts#unfollow'
      post '/accounts/:id/block', to: 'accounts#block'
      post '/accounts/:id/unblock', to: 'accounts#unblock'
      post '/accounts/:id/mute', to: 'accounts#mute'
      post '/accounts/:id/unmute', to: 'accounts#unmute'
      post '/accounts/:id/note', to: 'accounts#note'

      # ステータス
      resources :statuses, only: %i[show create destroy update] do
        member do
          get :context
          get :history
          get :source
          post :favourite
          post :unfavourite
          post :reblog
          post :unreblog
          post :quote
          get :quoted_by
          get :reblogged_by
          get :favourited_by
          post :pin
          post :unpin
          post :bookmark
          post :unbookmark
        end
      end

      # タグ
      resources :tags, only: [:show] do
        member do
          post :follow
          post :unfollow
        end
      end

      # タイムライン
      get '/timelines/home', to: 'timelines#home'
      get '/timelines/public', to: 'timelines#public'
      get '/timelines/tag/:hashtag', to: 'timelines#tag'

      # インスタンス
      get '/instance', to: 'instance#show'

      # メディア
      resources :media, only: %i[create show update]

      # ダイレクトメッセージ
      resources :conversations, only: %i[index show destroy] do
        member do
          post :read
        end
      end

      # 通知
      resources :notifications, only: %i[index show] do
        collection do
          post :clear
        end
        member do
          post :dismiss
        end
      end

      # ストリーミングAPI
      get '/streaming', to: 'streaming#index'

      # ドメインブロック
      get '/domain_blocks', to: 'domain_blocks#index'
      post '/domain_blocks', to: 'domain_blocks#create'
      delete '/domain_blocks', to: 'domain_blocks#destroy'

      # カスタム絵文字
      get '/custom_emojis', to: 'custom_emojis#index'

      # ブックマーク
      get '/bookmarks', to: 'bookmarks#index'

      # お気に入り
      get '/favourites', to: 'favourites#index'

      # フォローリクエスト
      get '/follow_requests', to: 'follow_requests#index'
      post '/follow_requests/:id/authorize', to: 'follow_requests#authorize'
      post '/follow_requests/:id/reject', to: 'follow_requests#reject'

      # マーカー
      get '/markers', to: 'markers#index'
      post '/markers', to: 'markers#create'

      # リスト
      get '/lists', to: 'lists#index'
      post '/lists', to: 'lists#create'
      get '/lists/:id', to: 'lists#show'
      put '/lists/:id', to: 'lists#update'
      delete '/lists/:id', to: 'lists#destroy'
      get '/lists/:id/accounts', to: 'lists#accounts'
      post '/lists/:id/accounts', to: 'lists#add_accounts'
      delete '/lists/:id/accounts', to: 'lists#remove_accounts'

      # 注目タグ
      get '/featured_tags', to: 'featured_tags#index'
      post '/featured_tags', to: 'featured_tags#create'
      delete '/featured_tags/:id', to: 'featured_tags#destroy'
      get '/featured_tags/suggestions', to: 'featured_tags#suggestions'

      # フォロー中のタグ
      get '/followed_tags', to: 'followed_tags#index'

      # 投票
      resources :polls, only: [:show] do
        member do
          post :vote, path: 'votes'
        end
      end

      # 予約投稿
      resources :scheduled_statuses, only: %i[index show update destroy]

      # Endorsements (stub)
      get '/endorsements', to: 'endorsements#index'
      post '/accounts/:id/pin', to: 'endorsements#create'
      delete '/accounts/:id/unpin', to: 'endorsements#destroy'

      # レポート（スタブ）
      post '/reports', to: 'reports#create'

      # サジェスト
      get '/suggestions', to: 'suggestions#index'
      delete '/suggestions/:id', to: 'suggestions#destroy'

      # トレンド
      get '/trends', to: 'trends#index'
      get '/trends/tags', to: 'trends#tags'
      get '/trends/statuses', to: 'trends#statuses'
      get '/trends/links', to: 'trends#links'

      # フィルター
      resources :filters

      # 設定
      get '/preferences', to: 'preferences#show'

      # お知らせ
      get '/announcements', to: 'announcements#index'
      post '/announcements/:id/dismiss', to: 'announcements#dismiss'

      # プッシュ通知登録
      namespace :push do
        get '/subscription', to: 'subscription#show'
        post '/subscription', to: 'subscription#create'
        put '/subscription', to: 'subscription#update'
        delete '/subscription', to: 'subscription#destroy'
      end

      # Admin API
      namespace :admin do
        get '/dashboard', to: 'dashboard#show'

        resources :accounts, only: %i[index show destroy] do
          member do
            post :enable
            post :suspend
          end
        end

        resources :reports, only: %i[index show] do
          member do
            post :assign_to_self
            post :unassign
            post :resolve
            post :reopen
          end
        end
      end
    end
  end
end
