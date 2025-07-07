# frozen_string_literal: true

# メディア・アセット関連ルート
Rails.application.routes.draw do
  # メディアファイル配信
  get '/media/:id', to: 'media#show', as: :media_file
  get '/media/:id/thumb', to: 'media#thumbnail', as: :media_thumbnail
end