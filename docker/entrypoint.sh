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
    
    if [ -z "$ACTIVITYPUB_DOMAIN" ]; then
        echo "ERROR: ACTIVITYPUB_DOMAINが必要です"
        echo "docker-compose.ymlまたは.envファイルでACTIVITYPUB_DOMAINを設定してください"
        exit 1
    fi
    
    if [ -z "$ACTIVITYPUB_PROTOCOL" ]; then
        echo "WARNING: ACTIVITYPUB_PROTOCOLが設定されていません、httpsをデフォルトとします"
        export ACTIVITYPUB_PROTOCOL=https
    fi
    
    echo "OK: 環境変数検証完了"
    echo "  ドメイン: $ACTIVITYPUB_DOMAIN"
    echo "  プロトコル: $ACTIVITYPUB_PROTOCOL"
}

# データベースセットアップ
setup_database() {
    echo "データベースをセットアップ中..."
    
    cd /app
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # データベースが存在するかチェック  
    RAILS_ENV=${RAILS_ENV:-development}
    DB_FILE="storage/${RAILS_ENV}.sqlite3"
    if [ ! -f "$DB_FILE" ]; then
        echo "データベースを作成中..."
        bundle exec rails db:create
        bundle exec rails db:migrate
        echo "OK: データベース作成とマイグレーション完了"
    else
        echo "データベースが存在します、マイグレーションを実行中..."
        bundle exec rails db:migrate
        echo "OK: データベースマイグレーション完了"
    fi
}

# 必要に応じてアセットをプリコンパイル
prepare_assets() {
    echo "アセットを準備中..."
    
    cd /app
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # 本番環境またはアセットが存在しない場合のみプリコンパイル
    if [ "$RAILS_ENV" = "production" ] || [ ! -d "public/assets" ]; then
        echo "アセットをプリコンパイル中..."
        bundle exec rails assets:precompile
        echo "OK: アセットプリコンパイル完了"
    else
        echo "OK: アセット準備済み"
    fi
    
    # 開発環境でTailwind CSS watcherを利用可能にする
    if [ "$RAILS_ENV" = "development" ]; then
        echo "開発モード: Tailwind CSSはオンデマンドでコンパイルされます"
        # 開発用にTailwind CSSビルドプロセスをバックグラウンド開始
        if [ -f "package.json" ] && grep -q "build:css" package.json; then
            echo "Tailwind CSS watcherを開始中..."
            npm run build:css &
            TAILWIND_PID=$!
            echo $TAILWIND_PID > tmp/pids/tailwind.pid
            echo "OK: Tailwind CSS watcher開始 (PID: $TAILWIND_PID)"
        fi
    fi
}

# 古いプロセスをクリーンアップ
cleanup_processes() {
    echo "プロセスをクリーンアップ中..."
    
    # PIDファイルを削除
    rm -f tmp/pids/server.pid
    rm -f tmp/pids/solid_queue.pid
    rm -f tmp/pids/tailwind.pid
    
    echo "OK: プロセスクリーンアップ完了"
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
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    setup_database
    prepare_assets
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