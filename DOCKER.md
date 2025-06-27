# letter - Docker Guide

このドキュメントでは、DockerとDocker Composeを使用してletterを実行する方法を説明します。

## 🚀 クイックスタート

### 1. 前提条件
- Docker Engine 20.10+
- Docker Compose v2.0+

### 2. 環境設定
```bash
# 環境変数ファイルをコピー
cp .env.docker .env.docker.local

# 環境変数を編集（必要に応じて）
# 最低限、ACTIVITYPUB_DOMAINを設定してください
nano .env.docker.local
```

### 3. サーバ起動
```bash
# ビルドと起動
docker-compose up --build

# バックグラウンド実行
docker-compose up -d --build
```

### 4. アクセス確認
- Web UI: http://localhost:3000
- ヘルスチェック: http://localhost:3000/up
- WebFinger: http://localhost:3000/.well-known/webfinger?resource=acct:username@yourdomain

## ⚙️ 設定

### 環境変数
| 変数名 | 説明 | デフォルト値 | 必須 |
|--------|------|-------------|------|
| `ACTIVITYPUB_DOMAIN` | インスタンスのドメイン | localhost:3000 | ✅ |
| `ACTIVITYPUB_PROTOCOL` | プロトコル (http/https) | http | ❌ |
| `INSTANCE_NAME` | インスタンス名 | letter | ❌ |
| `RAILS_ENV` | Rails環境 | development | ❌ |
| `S3_ENABLED` | R2オブジェクトストレージ使用 | false | ❌ |
| `S3_BUCKET` | R2バケット名 | - | S3_ENABLED=trueの場合必須 |
| `S3_REGION` | R2リージョン | auto | ❌ |
| `S3_ACCESS_KEY_ID` | R2アクセスキーID | - | S3_ENABLED=trueの場合必須 |
| `S3_SECRET_ACCESS_KEY` | R2シークレットキー | - | S3_ENABLED=trueの場合必須 |
| `S3_ENDPOINT` | R2エンドポイント | - | S3_ENABLED=trueの場合必須 |

### ポートマッピング
docker-compose.ymlでポートを変更できます：
```yaml
ports:
  - "8080:3000"  # ホストポート8080でアクセス
```

### データ永続化
以下のディレクトリが自動的にマウントされます：
- `./storage` - SQLiteデータベース
- `./log` - ログファイル
- `./storage` - Active Storageファイル（R2使用時は不要）

## 🔧 管理コマンド

### ユーザ作成
```bash
# コンテナ内でインタラクティブにユーザ作成
docker-compose exec web ./bin/manage_accounts.sh

# または直接Rails consoleを使用
docker-compose exec web rails console
```

### OAuthトークン生成
```bash
docker-compose exec web ./bin/create_oauth_token.sh
```

### ドメイン変更
```bash
# 新しいドメインに切り替え
docker-compose exec web ./bin/switch_domain.sh your-new-domain.com https

# コンテナ再起動
docker-compose restart web
```

### ログ確認
```bash
# リアルタイムログ
docker-compose logs -f web

# Railsログのみ
docker-compose exec web tail -f log/development.log

# Solid Queueログのみ
docker-compose exec web tail -f log/solid_queue.log
```

## 🌐 本番環境での使用

### 1. 環境変数設定
```bash
# .env.docker.local を本番設定に変更
ACTIVITYPUB_DOMAIN=your-domain.com
ACTIVITYPUB_PROTOCOL=https
RAILS_ENV=production
SECRET_KEY_BASE=your_secret_key_here

# R2オブジェクトストレージ使用時（推奨）
S3_ENABLED=true
S3_BUCKET=your-bucket-name
S3_REGION=auto
S3_ACCESS_KEY_ID=your_access_key
S3_SECRET_ACCESS_KEY=your_secret_key
S3_ENDPOINT=https://your-account-id.r2.cloudflarestorage.com
```

### 2. リバースプロキシ設定
Nginx、Caddy、Traefikなどでリバースプロキシを設定：
```nginx
# Nginx例
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3. HTTPS設定
Let's Encryptやその他のSSL証明書を設定してください。

## 📊 モニタリング

### ヘルスチェック
```bash
# Docker composeのヘルスチェック確認
docker-compose ps

# 手動ヘルスチェック
curl http://localhost:3000/up
```

### メトリクス
```bash
# プロセス確認
docker-compose exec web ps aux

# ディスク使用量
docker-compose exec web df -h

# メモリ使用量
docker stats
```

## 🔍 トラブルシューティング

### よくある問題

#### 1. ポートが既に使用されている
```bash
# ポートを変更
# docker-compose.yml の ports を "3001:3000" に変更
```

#### 2. 権限エラー
```bash
# ディレクトリの権限を修正
sudo chown -R 1000:1000 db log public/system
```

#### 3. アセットが見つからない
```bash
# アセットを再ビルド
docker-compose exec web bundle exec rails assets:precompile
```

#### 4. データベースエラー
```bash
# データベースを再作成
docker-compose exec web rails db:drop db:create db:migrate
```

### ログ確認
```bash
# 全ログを確認
docker-compose logs web

# エラーログのみ
docker-compose logs web | grep -i error

# 特定の時間以降のログ
docker-compose logs --since="2024-01-01T00:00:00" web
```

## 🔄 アップデート

### 1. コードを更新
```bash
git pull origin main
```

### 2. 依存関係を更新
```bash
docker-compose build --no-cache
```

### 3. データベースマイグレーション
```bash
docker-compose exec web rails db:migrate
```

### 4. 再起動
```bash
docker-compose restart web
```

### 5. バックアップ
```bash
# データベースバックアップ
docker-compose exec web sqlite3 storage/production.sqlite3 ".backup /app/backup.db"

# ローカルストレージファイルバックアップ（R2未使用時）
tar -czf storage_backup.tar.gz storage/

# R2使用時はCloudflareの管理画面から設定
```
