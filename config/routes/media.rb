# frozen_string_literal: true

# メディア・アセット関連ルート
Rails.application.routes.draw do
  # メディアファイル配信
  get '/media/:id', to: 'media#show', as: :media_file
  get '/media/:id/thumb', to: 'media#thumbnail', as: :media_thumbnail

  # メディアプロキシ（リモートメディアのキャッシュ配信）
  get '/media_proxy/:id', to: 'media_proxy#show', as: :media_proxy
  get '/media_proxy/:id/small', to: 'media_proxy#small', as: :media_proxy_small
end