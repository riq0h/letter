Rails.application.routes.draw do
  # ヘルスチェックエンドポイント
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # PWAファイル
  get 'service-worker' => 'rails/pwa#service_worker', :as => :pwa_service_worker
  get 'manifest' => 'rails/pwa#manifest', :as => :pwa_manifest

  # ================================
  # ActivityPub連合ルート
  # ================================

  # ActivityPub Inbox
  post '/users/:username/inbox', to: 'inbox#create', as: :user_inbox

  # ActivityPub Outbox
  get '/users/:username/outbox', to: 'outbox#show', as: :user_outbox
  post '/users/:username/outbox', to: 'outbox#create'

  # ActivityPubアクタープロフィール  
  get '/users/:username', to: 'actors#show', as: :user_actor

  # WebFinger discovery
  get '/.well-known/webfinger', to: 'well_known#webfinger'
  get '/.well-known/host-meta', to: 'well_known#host_meta'
  get '/.well-known/nodeinfo', to: 'well_known#nodeinfo'

  # NodeInfo
  get '/nodeinfo/2.1', to: 'nodeinfo#show'

  # ActivityPubアクティビティエンドポイント
  get '/users/:username/followers', to: 'followers#show'
  get '/users/:username/following', to: 'following#show'
  get '/users/:username/collections/featured', to: 'featured#show'

  # ActivityPubオブジェクトエンドポイント
  get '/users/:username/posts/:id', to: 'objects#show'
  get '/activities/:id', to: 'activities#show'

  # Shared inbox
  post '/inbox', to: 'shared_inboxes#create'

  # ================================
  # フロントエンドルート
  # ================================

  # ホームページ
  root 'home#index'

  # RSS/Atom feeds
  get '/@:username.rss', to: 'feeds#user', format: :rss
  get '/local.atom', to: 'feeds#local', format: :atom

  # ユーザプロフィール
  get '/@:username', to: 'profiles#show', as: :profile
  # 個別投稿表示
  get '/@:username/:id', to: 'posts#show_html', as: :post_html

  # API形式URLからフロントエンド形式URLへのリダイレクト
  get '/users/:username/posts/:id', to: 'posts#redirect_to_frontend', as: :post_redirect

  # 認証・管理
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: :logout
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

  # ================================
  # Mastodon API (サードパーティクライアント用)
  # ================================

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
      resources :statuses, only: [:show, :create, :destroy, :update] do
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
      resources :media, only: [:create, :show, :update]

      # ダイレクトメッセージ
      resources :conversations, only: [:index, :show, :destroy] do
        member do
          post :read
        end
      end

      # 通知
      resources :notifications, only: [:index, :show] do
        collection do
          post :clear
        end
        member do
          post :dismiss
        end
      end

      # ストリーミング
      get '/streaming', to: 'streaming#index'
      
      # サーバ通知イベント
      namespace :streaming do
        get '/stream', to: 'sse#stream'
      end

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
      resources :scheduled_statuses, only: [:index, :show, :update, :destroy]
      
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
        
        resources :accounts, only: [:index, :show, :destroy] do
          member do
            post :enable
            post :suspend
          end
        end
        
        resources :reports, only: [:index, :show] do
          member do
            post :assign_to_self
            post :unassign
            post :resolve
            post :reopen
          end
        end
      end
    end

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
      
      # フィルター (v2)
      resources :filters
      
      # メディア (v2)
      resources :media, only: [:create]
    end
  end

  # ================================
  # Action Cable (WebSocket)
  # ================================
  mount ActionCable.server => '/cable'

  # ================================
  # OAuth 2.0 Routes
  # ================================
  
  use_doorkeeper


  # ================================
  # Media & Assets
  # ================================

  # メディアファイル配信
  get '/media/:id', to: 'media#show', as: :media_file
  get '/media/:id/thumb', to: 'media#thumbnail', as: :media_thumbnail

  # ================================
  # 追加ルート
  # ================================


  # 静的ページ
  get '/about', to: 'pages#about'

  # 検索
  get '/search/index', to: 'search#index', as: :search_index

  # エラーページ
  get '/404', to: 'errors#not_found'
  get '/500', to: 'errors#internal_server_error'
  
  # 開発環境でのテスト用
  get '/test_500', to: 'errors#test_internal_server_error' if Rails.env.development?
  
  # 404エラー用のキャッチオールルート（最後に置く、Active Storageパスは除外）
  match '*path', to: 'errors#not_found', via: :all, constraints: ->(req) { 
    !req.path.start_with?('/rails/active_storage') 
  }
end
