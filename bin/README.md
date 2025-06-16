# Letter ActivityPub Instance Management Scripts

bin/ディレクトリには、ActivityPub機能を管理するためのスクリプトが含まれています。

## 📋 スクリプト一覧

### 🚀 サーバ管理

#### `start_server.sh`
**用途**: サーバ起動（詳細診断付き）  
**使用法**: `./start_server.sh`  
**説明**: .envファイルから環境変数を読み込み、データベース健全性チェック、Actor URL修正を実行してからRailsサーバとSolid Queueワーカーを起動します。

#### `cleanup_and_start.sh`
**用途**: 強制リセット＆再起動  
**使用法**: `./cleanup_and_start.sh`  
**説明**: 全プロセスを強制終了し、設定を修正してから再起動します。問題発生時に使用。

#### `load_env.sh`
**用途**: 環境変数読み込みヘルパー  
**使用法**: `source bin/load_env.sh`  
**説明**: .envファイルから環境変数を確実に読み込み、Rails runnerのラッパー関数を提供します。

### 🔧 設定管理

#### `switch_domain.sh`
**用途**: ドメイン変更  
**使用法**: `./switch_domain.sh <新しいドメイン> [プロトコル]`  
**例**: `./switch_domain.sh abc123.serveo.net https`  
**説明**: ActivityPubドメインを変更し、全ユーザのURLを更新します。

#### `check_domain.sh`
**用途**: 現在の設定確認  
**使用法**: `./check_domain.sh`  
**説明**: ドメイン設定、サーバ状態、データベース統計、エンドポイントの動作を確認します。

### 👤 ユーザ管理

#### `manage_accounts.sh`
**用途**: アカウント管理  
**使用法**: `./manage_accounts.sh`  
**説明**: 2個制限を考慮したアカウント作成・削除を管理。既存アカウントの状況に応じて適切な操作を案内します。

#### `create_oauth_token.sh`
**用途**: OAuth トークン生成  
**使用法**: `./create_oauth_token.sh`  
**説明**: 指定したユーザ用のOAuthアクセストークンを生成します。API使用に必要。

#### `delete_account.sh`
**用途**: アカウント削除  
**使用法**: `./delete_account.sh <ユーザ名またはID>`  
**例**: `./delete_account.sh tester` または `./delete_account.sh 4`  
**説明**: 指定したアカウントとすべての関連データを完全に削除します。OAuth tokens、投稿、フォロー関係、メディアなど、すべての依存レコードを適切な順序で削除し、データベースの整合性を保ちます。

### 📝 テストデータ生成

#### `create_test_posts.sh`
**用途**: テスト投稿生成  
**使用法**: `./create_test_posts.sh`  
**説明**: 英語、日本語、混在テキストの投稿を各20件（計60件）生成します。

### 🔧 メンテナンス

#### `fix_follow_counts.sh`
**用途**: フォローカウント修正  
**使用法**: `./fix_follow_counts.sh`  
**説明**: データベース内のフォローカウントを実際の関係数に合わせて修正します。

#### `test_follow.sh`
**用途**: フォローシステムテスト  
**使用法**: `./test_follow.sh`  
**説明**: フォローシステム（FollowService、WebFingerService）の動作確認を行います。

#### `migrate_to_r2.sh`
**用途**: Cloudflare R2移行  
**使用法**: `./migrate_to_r2.sh`  
**説明**: ローカルストレージの画像をCloudflare R2に移行します。設定完了後に使用。

## 🔧 環境変数の確実な読み込み

### load_env.sh の使用方法

環境変数読み込み問題を解決するため、`load_env.sh`ヘルパーを使用してください：

```bash
# 環境変数を読み込んでからRails runnerを実行
source bin/load_env.sh
run_with_env "puts Rails.application.config.activitypub.base_url"

# または一行で
source bin/load_env.sh && run_with_env "your_ruby_code"
```

### 主な機能
- `.env`ファイルの確実な読み込み
- 必須環境変数のバリデーション
- Rails runnerのラッパー関数 `run_with_env()`

## 📖 使用手順

### 初回セットアップ
```bash
# 1. アカウント管理
./manage_accounts.sh

# 2. OAuthトークン生成
./create_oauth_token.sh

# 3. テスト投稿生成（オプション）
./create_test_posts.sh

# 4. フォローシステムのテスト
./test_follow.sh
```

### アバター設定（Mastodon API準拠）
```bash
# API経由でアバター設定（multipart/form-data）
curl -X PATCH \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "avatar=@/path/to/image.png" \
  "https://YOUR_DOMAIN/api/v1/accounts/update_credentials"
```

### 日常運用
```bash
# サーバ起動
./start_server.sh

# 設定確認
./check_domain.sh

# ドメイン変更（トンネルURL期限切れ時）
./switch_domain.sh 新しいドメイン.serveo.net https
```

### トラブルシューティング
```bash
# 問題発生時の強制リセット
./cleanup_and_start.sh

# 通常起動（詳細診断付き）
./start_server.sh

# アカウント削除（問題のあるアカウントを削除）
./delete_account.sh problem_user
```

## ⚙️ 前提条件

- `.env` ファイルが適切に設定されていること
- Ruby on Rails環境が構築されていること
- 必要なgemがインストールされていること
- jq（JSONパーサー）がインストールされていること

## 📁 ファイル構成

```
bin/
├── README.md                      # このファイル
├── load_env.sh                   # 環境変数読み込みヘルパー
├── start_server.sh               # サーバ起動（詳細診断付き）
├── cleanup_and_start.sh          # 強制リセット＆再起動
├── switch_domain.sh              # ドメイン変更
├── check_domain.sh               # 設定確認・診断
├── manage_accounts.sh            # アカウント管理（2個制限対応）
├── create_oauth_token.sh         # OAuthトークン生成
├── delete_account.sh             # アカウント削除
├── create_test_posts.sh          # テスト投稿生成
├── fix_follow_counts.sh          # フォローカウント修正
├── test_follow.sh                # フォローシステムテスト
└── migrate_to_r2.sh              # Cloudflare R2移行
```

## 🔍 よくある問題と解決方法

### サーバが起動しない
```bash
./cleanup_and_start.sh
```

### 環境変数が読み込まれない
```bash
# .envファイルの確認
cat .env

# 環境変数読み込みヘルパーを使用
source bin/load_env.sh
run_with_env "puts Rails.application.config.activitypub.base_url"

# 設定状態の確認
./check_domain.sh
```

### ドメインが変更されない
```bash
# 全プロセス停止後にドメイン変更
pkill -f "rails\|solid"
./switch_domain.sh 新しいドメイン
```

### Solid Queueプロセスが多すぎる
```bash
./cleanup_and_start.sh
```

## 📝 ログファイル

- `log/development.log` - Railsアプリケーションログ
- `log/solid_queue.log` - Solid Queueワーカーログ

## 🔗 関連コマンド

```bash
# プロセス確認
ps aux | grep -E "rails|solid"

# ログ確認
tail -f log/development.log log/solid_queue.log

# 環境変数確認
source bin/load_env.sh

# API テスト（トークンが必要）
curl -H "Authorization: Bearer YOUR_TOKEN" \
     "https://YOUR_DOMAIN/api/v1/accounts/verify_credentials"

# フォローシステムのテスト
source bin/load_env.sh && run_with_env "
  tester = Actor.find_by(username: 'tester', local: true)
  puts \"Base URL: #{Rails.application.config.activitypub.base_url}\"
"
```

## 📞 サポート

問題が発生した場合は、まず `./check_domain.sh` で現在の状態を確認してください。それでも解決しない場合は、開発者にお問い合わせください。
