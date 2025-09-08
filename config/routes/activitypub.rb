# frozen_string_literal: true

# ActivityPub連合関連ルート
Rails.application.routes.draw do
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
  get '/nodeinfo/2.0', to: 'nodeinfo#show'
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
end