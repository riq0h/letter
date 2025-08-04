#!/bin/bash
set -e

# Dockerエントリーポイント
# データベースセットアップ、環境検証、プロセス管理を処理

# bundlerの環境を設定（グローバル）
export BUNDLE_GEMFILE=/app/Gemfile
export BUNDLE_PATH=/usr/local/bundle
export PATH="/usr/local/bundle/bin:$PATH"

echo "=== アプリケーション開始 ==="

# 依存関係の待機関数
wait_for_dependencies() {
    echo "依存関係をチェック中..."
    # 必要に応じてデータベース接続チェックを追加
    echo "OK: 依存関係準備完了"
}

# 必要な環境変数を検証
validate_environment() {
    echo "環境変数を検証中..."
    
    # 必須環境変数のチェック
    if [ -z "$ACTIVITYPUB_DOMAIN" ]; then
        echo "ERROR: ACTIVITYPUB_DOMAINが必要です"
        echo "docker-compose.ymlまたは.envファイルでACTIVITYPUB_DOMAINを設定してください"
        exit 1
    fi
    
    # プロトコルのデフォルト設定
    if [ -z "$ACTIVITYPUB_PROTOCOL" ]; then
        if [ "$RAILS_ENV" = "production" ]; then
            echo "WARNING: ACTIVITYPUB_PROTOCOLが設定されていません、httpsをデフォルトとします"
            export ACTIVITYPUB_PROTOCOL=https
        else
            echo "INFO: ACTIVITYPUB_PROTOCOLが設定されていません、httpをデフォルトとします"
            export ACTIVITYPUB_PROTOCOL=http
        fi
    fi
    
    # SOLID_QUEUE_IN_PUMAのデフォルト設定
    if [ -z "$SOLID_QUEUE_IN_PUMA" ]; then
        if [ "$RAILS_ENV" = "production" ]; then
            export SOLID_QUEUE_IN_PUMA=false
            echo "INFO: SOLID_QUEUE_IN_PUMAを本番環境デフォルト（false）に設定"
        else
            export SOLID_QUEUE_IN_PUMA=true
            echo "INFO: SOLID_QUEUE_IN_PUMAを開発環境デフォルト（true）に設定"
        fi
    fi
    
    # 本番環境の場合はSECRET_KEY_BASEをチェック・生成
    if [ "$RAILS_ENV" = "production" ] && [ -z "$SECRET_KEY_BASE" ]; then
        echo "本番環境用のSECRET_KEY_BASEを生成中..."
        export SECRET_KEY_BASE=$(bundle exec rails secret)
        echo "OK: SECRET_KEY_BASEを生成しました"
    fi
    
    # 本番環境での追加チェック
    if [ "$RAILS_ENV" = "production" ]; then
        echo "本番環境設定を確認中..."
        
        if [ "$ACTIVITYPUB_DOMAIN" = "localhost" ] || echo "$ACTIVITYPUB_DOMAIN" | grep -q "localhost"; then
            echo "WARNING: 本番環境でlocalhostドメインが設定されています"
        fi
        
        if [ "$ACTIVITYPUB_PROTOCOL" != "https" ]; then
            echo "WARNING: ActivityPubはHTTPS必須です。本番環境ではhttpsを使用してください"
        fi
        
        if [ -z "$VAPID_PUBLIC_KEY" ] || [ -z "$VAPID_PRIVATE_KEY" ]; then
            echo "WARNING: VAPIDキーが設定されていません。WebPush機能は無効です"
            echo "         以下のコマンドでVAPIDキーを生成してください:"
            echo "         bundle exec rails webpush:generate_vapid_key"
        fi
        
        # 必須設定の最終チェック
        missing_keys=""
        if [ -z "$VAPID_PUBLIC_KEY" ]; then
            missing_keys="$missing_keys VAPID_PUBLIC_KEY"
        fi
        if [ -z "$VAPID_PRIVATE_KEY" ]; then
            missing_keys="$missing_keys VAPID_PRIVATE_KEY"
        fi
        
        if [ -n "$missing_keys" ]; then
            echo "WARNING: 以下の必須設定が不足しています:$missing_keys"
        fi
    fi
    
    echo "OK: 環境変数検証完了"
    echo "  ドメイン: $ACTIVITYPUB_DOMAIN"
    echo "  プロトコル: $ACTIVITYPUB_PROTOCOL"
    echo "  環境: ${RAILS_ENV:-development}"
    echo "  Solid Queue in Puma: ${SOLID_QUEUE_IN_PUMA:-true}"
}

# 古いプロセスをクリーンアップ
cleanup_processes() {
    echo "プロセスとファイルをクリーンアップ中..."
    
    # 必要なディレクトリを作成
    mkdir -p tmp/pids tmp/cache log
    
    # PIDファイルを削除
    rm -f tmp/pids/server.pid
    rm -f tmp/pids/solid_queue.pid
    rm -f tmp/pids/tailwind.pid
    
    # ログファイルのクリーンアップ（サイズが大きい場合）
    if [ -f "log/${RAILS_ENV:-development}.log" ]; then
        log_size=$(wc -c < "log/${RAILS_ENV:-development}.log" 2>/dev/null || echo "0")
        if [ "$log_size" -gt 10485760 ]; then  # 10MB以上の場合
            echo "大きなログファイルをクリアしています..."
            > "log/${RAILS_ENV:-development}.log"
        fi
    fi
    
    # テンポラリファイルのクリーンアップ
    if [ -d "tmp/cache" ]; then
        find tmp/cache -type f -mtime +1 -delete 2>/dev/null || true
    fi
    
    echo "OK: プロセスとファイルのクリーンアップ完了"
}

# Solid Queueをバックグラウンドで開始
start_solid_queue() {
    echo "Solid Queueワーカーを開始中..."
    
    cd /app
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # Pumaで実行していない場合のみ開始（SOLID_QUEUE_IN_PUMAをチェック）
    if [ "$SOLID_QUEUE_IN_PUMA" != "true" ]; then
        # Solid Queueをバックグラウンドプロセスとして開始
        bundle exec bin/jobs &
        SOLID_QUEUE_PID=$!
        echo $SOLID_QUEUE_PID > tmp/pids/solid_queue.pid
        
        echo "OK: Solid Queue開始 (PID: $SOLID_QUEUE_PID)"
    else
        echo "OK: Solid QueueはPumaプロセス内で実行されます"
    fi
}

# グレースフルシャットダウンハンドラー
shutdown_handler() {
    echo ""
    echo "=== アプリケーション終了中 ==="
    
    # Solid Queueを停止
    if [ -f tmp/pids/solid_queue.pid ]; then
        SOLID_QUEUE_PID=$(cat tmp/pids/solid_queue.pid)
        if kill -0 $SOLID_QUEUE_PID 2>/dev/null; then
            echo "Solid Queueを停止中 (PID: $SOLID_QUEUE_PID)..."
            kill -TERM $SOLID_QUEUE_PID
            wait $SOLID_QUEUE_PID 2>/dev/null || true
        fi
        rm -f tmp/pids/solid_queue.pid
    fi
    
    # Tailwind CSS watcherを停止
    if [ -f tmp/pids/tailwind.pid ]; then
        TAILWIND_PID=$(cat tmp/pids/tailwind.pid)
        if kill -0 $TAILWIND_PID 2>/dev/null; then
            echo "Tailwind CSS watcherを停止中 (PID: $TAILWIND_PID)..."
            kill -TERM $TAILWIND_PID
            wait $TAILWIND_PID 2>/dev/null || true
        fi
        rm -f tmp/pids/tailwind.pid
    fi
    
    echo "OK: グレースフルシャットダウン完了"
    exit 0
}

# シグナルハンドラーを設定
trap shutdown_handler SIGTERM SIGINT

# メイン実行
main() {
    wait_for_dependencies
    validate_environment
    cleanup_processes
    
    # 作業ディレクトリを設定
    cd /app
    
    # ファイル権限を修正
    chmod 755 . 2>/dev/null || true
    mkdir -p config 2>/dev/null || true
    touch .env 2>/dev/null || true
    touch .env.template 2>/dev/null || true
    touch Gemfile.lock 2>/dev/null || true
    touch config/cache.yml 2>/dev/null || true
    touch config/queue.yml 2>/dev/null || true
    touch config/cable.yml 2>/dev/null || true
    chmod 644 .env .env.template Gemfile.lock config/cache.yml config/queue.yml config/cable.yml 2>/dev/null || true
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # 環境変数設定
    RAILS_ENV=${RAILS_ENV:-development}
    secret_key=${SECRET_KEY_BASE:-$(bundle exec rails secret)}
    
    # bin/setupを環境変数付きで実行
    echo "bin/setupを実行中..."
    RAILS_ENV="${RAILS_ENV}" SECRET_KEY_BASE="${secret_key}" bundle exec ruby bin/setup
    start_solid_queue
    
    echo "=== アプリケーション準備完了 ==="
    
    echo "Railsサーバを開始中..."
    echo "アクセス可能: $ACTIVITYPUB_PROTOCOL://$ACTIVITYPUB_DOMAIN"
    echo ""
    
    # メインコマンドを実行
    exec "$@"
}

# メイン関数を実行
main "$@"