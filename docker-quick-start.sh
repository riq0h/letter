#!/bin/bash

# Dockerクイックスタート

set -e

echo "letter Dockerクイックスタート"
echo "=================================================="
echo ""

# Dockerがインストールされているかチェック
if ! command -v docker &> /dev/null; then
    echo "ERROR: Dockerがインストールされていません。まずDockerをインストールしてください。"
    echo "参考: https://docs.docker.com/get-docker/"
    exit 1
fi

# Docker Composeがインストールされているかチェック（両方の形式をチェック）
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "ERROR: Docker Composeがインストールされていません。まずDocker Composeをインストールしてください。"
    echo "参考: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "OK: DockerとDocker Composeがインストールされています"
echo ""

# 環境ファイルが存在しない場合は作成
if [ ! -f ".env" ]; then
    echo "INFO: 環境設定を作成中..."
    echo ""
    
    # 環境を選択
    echo "環境を選択してください:"
    echo "1) 開発環境"
    echo "2) 本番環境"
    read -p "選択してください (1-2) [1]: " env_choice
    env_choice=${env_choice:-1}
    
    if [ "$env_choice" == "2" ]; then
        rails_env="production"
        default_protocol="https"
    else
        rails_env="development"
        default_protocol="http"
    fi
    
    # ドメインを入力
    if [ "$rails_env" == "production" ]; then
        read -p "ドメインを入力してください: " domain
        if [ -z "$domain" ]; then
            echo "ERROR: 本番環境ではドメインの入力が必須です"
            exit 1
        fi
    else
        read -p "ドメインを入力してください (localhost:3002の場合はEnterを押してください): " domain
        domain=${domain:-localhost:3002}
    fi
    
    # プロトコルを自動判定
    if [[ $domain == *"localhost"* ]]; then
        protocol="http"
    else
        protocol=$default_protocol
    fi
    
    # SECRET_KEY_BASEを生成（本番環境の場合）
    if [ "$rails_env" == "production" ]; then
        if command -v openssl &> /dev/null; then
            secret_key_base=$(openssl rand -hex 64)
        else
            echo "WARN: opensslがインストールされていません。SECRET_KEY_BASEを手動で設定してください。"
            secret_key_base=""
        fi
        port="3001"
    else
        secret_key_base=""
        port="3002"
    fi
    
    cat > .env << EOF
# ActivityPub設定
ACTIVITYPUB_DOMAIN=$domain
ACTIVITYPUB_PROTOCOL=$protocol

# Cloudflare R2オブジェクトストレージ設定
S3_ENABLED=false
S3_ENDPOINT=
S3_BUCKET=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
S3_ALIAS_HOST=

# Rails設定
RAILS_ENV=$rails_env
SECRET_KEY_BASE=$secret_key_base

# ポート設定
PORT=$port
EOF
    
    echo "OK: 環境ファイルが作成されました: .env"
    
    if [ "$rails_env" == "production" ] && [ -z "$secret_key_base" ]; then
        echo "WARN: SECRET_KEY_BASEが設定されていません。本番環境では必須です。"
        echo "      以下のコマンドで生成してください:"
        echo "      openssl rand -hex 64"
    fi
else
    echo "OK: 環境ファイルが存在します: .env"
    # 環境変数を読み込んで環境を判定
    if grep -q "RAILS_ENV=production" .env; then
        rails_env="production"
    else
        rails_env="development"
    fi
fi

echo ""

# 必要なディレクトリを作成
echo "INFO: 必要なディレクトリを作成中..."
mkdir -p storage log public/uploads
echo "OK: ディレクトリが作成されました"
echo ""

# ユーザに何をするか尋ねる
echo "何をしますか？"
echo "1) ビルドしてアプリを開始（バックグラウンド）"
echo "2) アプリを開始（ビルドなし・バックグラウンド）"
echo "3) ビルドのみ（開始しない）"
echo "4) ログを表示"
echo "5) アプリを停止"
echo "6) 統合管理ツールを起動"
echo "7) クリーンアップ（コンテナとイメージを削除）"
echo ""
read -p "選択してください (1-7): " choice

# docker-composeファイルの選択
if [ "$rails_env" == "production" ]; then
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
else
    COMPOSE_FILES=""
fi

case $choice in
    1)
        echo "INFO: letterをバックグラウンドでビルドして開始中..."
        $DOCKER_COMPOSE $COMPOSE_FILES up -d --build
        echo ""
        echo "OK: letterがバックグラウンドで実行中です"
        # ポート情報を取得（.envファイルから環境変数を読み込む）
        if [ -f ".env" ]; then
            source .env
        fi
        
        if [ "$rails_env" == "production" ]; then
            access_url="${ACTIVITYPUB_PROTOCOL:-https}://${ACTIVITYPUB_DOMAIN}"
            healthcheck_url="${ACTIVITYPUB_PROTOCOL:-https}://${ACTIVITYPUB_DOMAIN}/up"
        else
            access_url="${ACTIVITYPUB_PROTOCOL:-http}://${ACTIVITYPUB_DOMAIN:-localhost:3002}"
            healthcheck_url="${ACTIVITYPUB_PROTOCOL:-http}://${ACTIVITYPUB_DOMAIN:-localhost:3002}/up"
        fi
        echo "アクセス: $access_url"
        echo "ヘルスチェック: $healthcheck_url"
        echo ""
        echo "便利なコマンド:"
        echo "  ログ表示: $DOCKER_COMPOSE $COMPOSE_FILES logs -f"
        echo "  停止: $DOCKER_COMPOSE $COMPOSE_FILES down"
        echo "  再起動: $DOCKER_COMPOSE $COMPOSE_FILES restart"
        echo "  管理ツール: $DOCKER_COMPOSE $COMPOSE_FILES exec web rails runner bin/letter_manager.rb"
        ;;
    2)
        echo "INFO: letterをバックグラウンドで開始中..."
        $DOCKER_COMPOSE $COMPOSE_FILES up -d
        echo ""
        echo "OK: letterがバックグラウンドで実行中です"
        # ポート情報を取得（.envファイルから環境変数を読み込む）
        if [ -f ".env" ]; then
            source .env
        fi
        
        if [ "$rails_env" == "production" ]; then
            access_url="${ACTIVITYPUB_PROTOCOL:-https}://${ACTIVITYPUB_DOMAIN}"
            healthcheck_url="${ACTIVITYPUB_PROTOCOL:-https}://${ACTIVITYPUB_DOMAIN}/up"
        else
            access_url="${ACTIVITYPUB_PROTOCOL:-http}://${ACTIVITYPUB_DOMAIN:-localhost:3002}"
            healthcheck_url="${ACTIVITYPUB_PROTOCOL:-http}://${ACTIVITYPUB_DOMAIN:-localhost:3002}/up"
        fi
        echo "アクセス: $access_url"
        echo "ヘルスチェック: $healthcheck_url"
        echo ""
        echo "便利なコマンド:"
        echo "  ログ表示: $DOCKER_COMPOSE $COMPOSE_FILES logs -f"
        echo "  停止: $DOCKER_COMPOSE $COMPOSE_FILES down"
        echo "  再起動: $DOCKER_COMPOSE $COMPOSE_FILES restart"
        echo "  管理ツール: $DOCKER_COMPOSE $COMPOSE_FILES exec web rails runner bin/letter_manager.rb"
        ;;
    3)
        echo "INFO: letterをビルド中..."
        $DOCKER_COMPOSE $COMPOSE_FILES build
        echo "OK: ビルドが完了しました"
        ;;
    4)
        echo "INFO: ログを表示中..."
        $DOCKER_COMPOSE logs -f
        ;;
    5)
        echo "INFO: letterを停止中..."
        $DOCKER_COMPOSE down
        echo "OK: letterが停止しました"
        ;;
    6)
        echo "INFO: 統合管理ツールを起動中..."
        $DOCKER_COMPOSE exec web rails runner bin/letter_manager.rb
        ;;
    7)
        echo "INFO: クリーンアップ中..."
        $DOCKER_COMPOSE down --rmi all --volumes --remove-orphans
        echo "OK: クリーンアップが完了しました"
        ;;
    *)
        echo "ERROR: 無効な選択です。スクリプトを再実行してください。"
        exit 1
        ;;
esac

echo ""
echo "処理が完了しました。"
