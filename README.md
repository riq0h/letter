# letter : General Letter Publication System based on ActivityPub / 一般書簡公衆化システム

<div align="center">
  <img src="/public/icon-192.png" alt="letter icon">
</div>

## 特徴

letterはRails8およびSQLite、Hotwireで構成されるミニマルなActivityPub実装であり、一般的に作成された電子書簡を速やかに公衆送信することができます。この実装系は以下の特徴を備えています。

・1インスタンス2アカウント制限  
・サードパーティクライアントの利用を前提とした軽量な設計  
・RedisやSidekiqを廃し、Solid QueueおよびSolid Cable、Solid Cacheで構成された外部非依存のバックエンド  
・マイクロブログの復権を意識した平易かつ高速なフロントエンド  
・ローカル投稿の全文検索に対応  
・Mastodon APIに準拠

## セットアップ（本番環境）

```
RAILS_ENV=production bin/setup
```

## セットアップ（Docker）

```
./docker-quick-start.sh
```

## 起動（Docker）

```
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

## 統合管理ツール

```
bin/letter_manager.rb
```

```
docker compose exec web rails runner bin/letter_manager.rb
```

## スクリーンショット

<div align="center">
  <img src="/public/post.png" alt="post screenshot">
</div>

<div align="center">
  <img src="/public/config.png" alt="config screenshot">
</div>
