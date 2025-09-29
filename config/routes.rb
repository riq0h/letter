# frozen_string_literal: true

Rails.application.routes.draw do
  # QuoteAuthorization endpoint for FEP-044f
  get '/quote_auth/:id', to: 'activity_pub/quote_authorizations#show', as: :quote_authorization
  # ヘルスチェックエンドポイント
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # PWAファイル
  get 'service-worker' => 'rails/pwa#service_worker', :as => :pwa_service_worker
  get 'manifest' => 'rails/pwa#manifest', :as => :pwa_manifest

  # ================================
  # 分割されたルートファイルを読み込み
  # ================================

  # ActivityPub連合関連ルート
  draw :activitypub

  # フロントエンド表示関連ルート
  draw :frontend

  # 管理・設定関連ルート
  draw :admin

  # Mastodon API v1
  draw :api_v1

  # Mastodon API v2
  draw :api_v2

  # メディア・アセット関連ルート
  draw :media

  # ================================
  # その他のシステム統合
  # ================================


  # OAuth 2.0 Routes
  use_doorkeeper

  # ================================
  # キャッチオールルート（最後に配置）
  # ================================
  
  # 404エラー用のキャッチオールルート（Active Storageパスは除外）
  match '*path', to: 'errors#not_found', via: :all, constraints: ->(req) { 
    !req.path.start_with?('/rails/active_storage')
  }
end