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
        fi
    fi
    
    echo "OK: 環境変数検証完了"
    echo "  ドメイン: $ACTIVITYPUB_DOMAIN"
    echo "  プロトコル: $ACTIVITYPUB_PROTOCOL"
    echo "  環境: ${RAILS_ENV:-development}"
}

# データベースセットアップ
setup_database() {
    echo "データベースをセットアップ中..."
    
    cd /app
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # storageディレクトリの確保
    mkdir -p storage
    
    RAILS_ENV=${RAILS_ENV:-development}
    
    # メインデータベースのセットアップ
    DB_FILE="storage/${RAILS_ENV}.sqlite3"
    if [ ! -f "$DB_FILE" ]; then
        echo "メインデータベースを作成中..."
        bundle exec rails db:create
        bundle exec rails db:migrate
        echo "OK: メインデータベース作成とマイグレーション完了"
    else
        echo "メインデータベースが存在します、マイグレーション確認中..."
        # マイグレーション状態をチェック
        migration_check=$(bundle exec rails db:migrate:status 2>&1)
        if echo "$migration_check" | grep -q "down"; then
            echo "未実行のマイグレーションがあります。実行中..."
            bundle exec rails db:migrate
            echo "OK: マイグレーション完了"
        else
            echo "OK: すべてのマイグレーションが完了しています"
        fi
    fi
    
    # Solid関連データベースファイルの作成
    echo "Solid関連データベースファイルを確認中..."
    
    CACHE_DB_FILE="storage/cache_${RAILS_ENV}.sqlite3"
    QUEUE_DB_FILE="storage/queue_${RAILS_ENV}.sqlite3"
    CABLE_DB_FILE="storage/cable_${RAILS_ENV}.sqlite3"
    
    # データベースファイルが存在しない場合は作成
    for db_info in "Cache:$CACHE_DB_FILE" "Queue:$QUEUE_DB_FILE" "Cable:$CABLE_DB_FILE"; do
        db_name=$(echo "$db_info" | cut -d: -f1)
        db_file=$(echo "$db_info" | cut -d: -f2)
        
        if [ ! -f "$db_file" ]; then
            echo "${db_name}データベースファイルを作成中..."
            # 空のSQLiteファイルを作成
            sqlite3 "$db_file" "SELECT 1;" 2>/dev/null || echo "⚠️  ${db_name}データベース作成に失敗しました"
        fi
    done
    
    echo "OK: Solid関連データベースファイル確認完了"
}

# 必要に応じてアセットをプリコンパイル
prepare_assets() {
    echo "アセットを準備中..."
    
    cd /app
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    # アセットビルドディレクトリを作成
    mkdir -p app/assets/builds
    
    # 本番環境またはアセットが存在しない場合のみプリコンパイル
    if [ "$RAILS_ENV" = "production" ] || [ ! -d "public/assets" ]; then
        echo "アセットをプリコンパイル中..."
        
        # Solid Components セットアップ
        if [ "$RAILS_ENV" = "production" ]; then
            echo "💾 Solid Cacheをセットアップ中..."
            if [ ! -f "config/cache.yml" ]; then
                echo "y" | bundle exec rails solid_cache:install 2>/dev/null || echo "⚠️  Solid Cacheのインストールをスキップしました"
            fi
            
            echo "📡 Solid Cableをセットアップ中..."
            if [ ! -f "config/cable.yml" ]; then
                echo "y" | bundle exec rails solid_cable:install 2>/dev/null || echo "⚠️  Solid Cableのインストールをスキップしました"
            fi
            
            echo "🚀 Solid Queueをセットアップ中..."
            if [ ! -f "config/queue.yml" ]; then
                echo "y" | bundle exec rails solid_queue:install 2>/dev/null || echo "⚠️  Solid Queueのインストールをスキップしました"
            fi
            
            # Solid関連データベースのスキーマ読み込み
            echo "🔧 Solid関連スキーマを読み込み中..."
            
            # Solid Queueスキーマ
            if [ -f "db/queue_schema.rb" ]; then
                bundle exec rails runner "
                  begin
                    original_connection = ActiveRecord::Base.connection_db_config.name
                    ActiveRecord::Base.establish_connection(:queue)
                    
                    schema_content = File.read(Rails.root.join('db/queue_schema.rb'))
                    eval(schema_content)
                    
                    puts 'SUCCESS: Solid Queue schema loaded'
                  rescue => e
                    puts 'ERROR: Solid Queue schema - ' + e.message
                  ensure
                    ActiveRecord::Base.establish_connection(original_connection.to_sym) if original_connection
                  end
                " || echo "⚠️  Solid Queueスキーマ読み込みに失敗しました"
            fi
            
            # Solid Cacheスキーマ（手動作成）
            bundle exec rails runner "
              begin
                original_connection = ActiveRecord::Base.connection_db_config.name
                ActiveRecord::Base.establish_connection(:cache)
                
                unless ActiveRecord::Base.connection.table_exists?('solid_cache_entries')
                  ActiveRecord::Base.connection.execute('
                    CREATE TABLE solid_cache_entries (
                      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                      key BLOB NOT NULL,
                      value BLOB NOT NULL,
                      created_at DATETIME NOT NULL,
                      key_hash INTEGER NOT NULL,
                      byte_size INTEGER NOT NULL
                    )
                  ')
                  ActiveRecord::Base.connection.execute('CREATE UNIQUE INDEX index_solid_cache_entries_on_key_hash ON solid_cache_entries (key_hash)')
                  ActiveRecord::Base.connection.execute('CREATE INDEX index_solid_cache_entries_on_byte_size ON solid_cache_entries (byte_size)')
                  puts 'SUCCESS: Solid Cache schema created'
                else
                  puts 'SUCCESS: Solid Cache schema exists'
                end
              rescue => e
                puts 'ERROR: Solid Cache schema - ' + e.message
              ensure
                ActiveRecord::Base.establish_connection(original_connection.to_sym) if original_connection
              end
            " || echo "⚠️  Solid Cacheスキーマ作成に失敗しました"
            
            # Solid Cableスキーマ
            if [ -f "db/cable_schema.rb" ]; then
                bundle exec rails runner "
                  begin
                    original_connection = ActiveRecord::Base.connection_db_config.name
                    ActiveRecord::Base.establish_connection(:cable)
                    
                    schema_content = File.read(Rails.root.join('db/cable_schema.rb'))
                    eval(schema_content)
                    
                    puts 'SUCCESS: Solid Cable schema loaded'
                  rescue => e
                    puts 'ERROR: Solid Cable schema - ' + e.message
                  ensure
                    ActiveRecord::Base.establish_connection(original_connection.to_sym) if original_connection
                  end
                " || echo "⚠️  Solid Cableスキーマ読み込みに失敗しました"
            elif [ -f "db/cable_structure.sql" ]; then
                echo "Solid Cable構造ファイルを読み込み中..."
                sqlite3 "storage/cable_${RAILS_ENV}.sqlite3" < db/cable_structure.sql 2>/dev/null || echo "⚠️  Solid Cable構造読み込みに失敗しました"
            fi
        fi
        
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
    
    # bundlerの環境を設定
    export BUNDLE_GEMFILE=/app/Gemfile
    export BUNDLE_PATH=/usr/local/bundle
    
    setup_database
    prepare_assets
    start_solid_queue
    
    echo "=== アプリケーション準備完了 ==="
    
    # 本番環境での最終確認
    if [ "$RAILS_ENV" = "production" ]; then
        echo "本番環境最終確認中..."
        
        # データベース接続確認
        if bundle exec rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" 2>/dev/null; then
            echo "✓ メインデータベース接続OK"
        else
            echo "✗ メインデータベース接続エラー"
        fi
        
        # Solid関連データベース確認
        for db_type in cache queue cable; do
            if bundle exec rails runner "
              begin
                ActiveRecord::Base.establish_connection(:${db_type})
                ActiveRecord::Base.connection.execute('SELECT 1')
                puts 'OK'
              rescue
                puts 'ERROR'
              ensure
                ActiveRecord::Base.establish_connection(:primary)
              end
            " 2>/dev/null | grep -q "OK"; then
                echo "✓ ${db_type}データベース接続OK"
            else
                echo "⚠️  ${db_type}データベース接続に問題があります"
            fi
        done
        
        echo "本番環境確認完了"
    fi
    
    echo "Railsサーバを開始中..."
    echo "アクセス可能: $ACTIVITYPUB_PROTOCOL://$ACTIVITYPUB_DOMAIN"
    echo ""
    
    # メインコマンドを実行
    exec "$@"
}

# メイン関数を実行
main "$@"
