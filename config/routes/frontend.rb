# frozen_string_literal: true

# フロントエンド表示関連ルート
Rails.application.routes.draw do
  # ホームページ
  root 'home#index'

  # RSS/Atom feeds
  get '/@:username.rss', to: 'feeds#user', format: :rss
  get '/local.atom', to: 'feeds#local', format: :atom

  # ユーザプロフィール
  get '/@:username', to: 'profiles#show', as: :profile
  # 個別投稿表示
  get '/@:username/:id', to: 'posts#show_html', as: :post_html
  # 投稿埋め込み
  get '/@:username/:id/embed', to: 'posts#embed', as: :embed_post

  # API形式URLからフロントエンド形式URLへのリダイレクト
  get '/users/:username/posts/:id', to: 'posts#redirect_to_frontend', as: :post_redirect
  get '/users/:username', to: 'profiles#redirect_to_frontend', as: :profile_redirect

  # 認証
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy', as: :logout

  # 静的ページ
  get '/about', to: 'pages#about'

  # 検索
  get '/search/index', to: 'search#index', as: :search_index

  # エラーページ
  get '/404', to: 'errors#not_found'
  get '/500', to: 'errors#internal_server_error'
  
  # 開発環境でのテスト用
  get '/test_500', to: 'errors#test_internal_server_error' if Rails.env.development?
end