# frozen_string_literal: true

# CORS設定でサードパーティクライアントからのAPIアクセスを許可
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'
    
    resource '/api/*',
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head],
             expose: ['Link', 'X-RateLimit-Reset', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-Request-Id']
  end

  allow do
    origins '*'
    
    resource '/oauth/*',
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end

  allow do
    origins '*'
    
    resource '/.well-known/*',
             headers: :any,
             methods: [:get, :options, :head]
  end

  # ActivityPub用
  allow do
    origins '*'
    
    resource '/users/*',
             headers: :any,
             methods: [:get, :options, :head],
             expose: ['Content-Type']
  end

  # NodeInfo用  
  allow do
    origins '*'
    
    resource '/nodeinfo/*',
             headers: :any,
             methods: [:get, :options, :head]
  end
end