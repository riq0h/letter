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
    
    # 環境変数設定
    secret_key=${SECRET_KEY_BASE:-$(bundle exec rails secret)}
    env_cmd="RAILS_ENV=${RAILS_ENV} SECRET_KEY_BASE=\"${secret_key}\""
    
    # メインデータベースのセットアップ
    DB_FILE="storage/${RAILS_ENV}.sqlite3"
    if [ ! -f "$DB_FILE" ]; then
        echo "メインデータベースを作成中..."
        eval "${env_cmd} bundle exec rails db:create"
        eval "${env_cmd} bundle exec rails db:migrate"
        echo "OK: メインデータベース作成とマイグレーション完了"
    else
        echo "メインデータベースが存在します、マイグレーション確認中..."
        migration_check=$(eval "${env_cmd} bundle exec rails db:migrate:status 2>&1")
        
        if echo "$migration_check" | grep -q "Schema migrations table does not exist yet" || ! [ $? -eq 0 ]; then
            echo "初回マイグレーションを実行中..."
            eval "${env_cmd} bundle exec rails db:migrate"
            echo "OK: 初回マイグレーション完了"
        else
            pending_migrations=$(echo "$migration_check" | grep -c "down" | head -1)
            if [ "$pending_migrations" -gt 0 ]; then
                echo "${pending_migrations}個の未実行マイグレーションがあります。実行中..."
                eval "${env_cmd} bundle exec rails db:migrate"
                echo "OK: マイグレーション完了"
            else
                echo "OK: すべてのマイグレーションが完了しています"
            fi
        fi
    fi
    
    # Solid関連データベースファイルの作成
    echo "Solid関連データベースファイルを確認中..."
    
    CACHE_DB_FILE="storage/cache_${RAILS_ENV}.sqlite3"
    QUEUE_DB_FILE="storage/queue_${RAILS_ENV}.sqlite3"
    CABLE_DB_FILE="storage/cable_${RAILS_ENV}.sqlite3"
    
    # データベースファイル作成
    for db_info in "Cache:$CACHE_DB_FILE:cache" "Queue:$QUEUE_DB_FILE:queue" "Cable:$CABLE_DB_FILE:cable"; do
        db_name=$(echo "$db_info" | cut -d: -f1)
        db_file=$(echo "$db_info" | cut -d: -f2)
        db_type=$(echo "$db_info" | cut -d: -f3)
        
        if [ ! -f "$db_file" ]; then
            echo "${db_name}データベースファイルを作成中..."
            sqlite3 "$db_file" "SELECT 1;" 2>/dev/null || echo "⚠️  ${db_name}データベース作成に失敗しました"
        else
            echo "${db_name}データベースファイルが存在します"
            
            # キャッシュデータベースの誤ったテーブル対策
            if [ "$db_type" = "cache" ]; then
                tables=$(sqlite3 "$db_file" ".tables" 2>/dev/null)
                if echo "$tables" | grep -q "actors\|objects\|activities"; then
                    echo "${db_name}データベースに誤ったテーブルが含まれています。再作成します..."
                    
                    current_migrations=""
                    if echo "$tables" | grep -q "schema_migrations"; then
                        current_migrations=$(sqlite3 "$db_file" "SELECT version FROM schema_migrations;" 2>/dev/null)
                    fi
                    
                    rm -f "$db_file"
                    sqlite3 "$db_file" "SELECT 1;" 2>/dev/null
                    echo "${db_name}データベースを再作成しました"
                    
                    if [ -n "$current_migrations" ]; then
                        echo "キャッシュデータベースのマイグレーション情報を復元中..."
                        sqlite3 "$db_file" "CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY);"
                        echo "$current_migrations" | while read -r version; do
                            [ -n "$version" ] && sqlite3 "$db_file" "INSERT OR IGNORE INTO schema_migrations (version) VALUES ('$version');"
                        done
                        echo "マイグレーション情報を復元しました"
                    fi
                fi
            fi
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
        
        # Solid関連の設定ファイルとスキーマを一括インストール
        echo "Solid関連コンポーネントのインストール..."
        
        # cache.ymlを手動で作成
        if [ ! -f "config/cache.yml" ]; then
            echo "cache.ymlが存在しないため、作成します..."
            cat > config/cache.yml << 'EOF'
default: &default
  database: cache
  store_options:
    max_age: <%= 1.week.to_i %>
    max_size: <%= 256.megabytes %>
    max_entries: <%= 10_000 %>

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
EOF
            echo "cache.ymlを作成しました"
        else
            echo "cache.ymlが既に存在します"
        fi
        
        if [ ! -f "config/queue.yml" ]; then
            echo "queue.ymlが存在しないため、Solid Queueをインストールします..."
            eval "${env_cmd} bundle exec rails solid_queue:install 2>/dev/null"
        else
            echo "queue.ymlが既に存在します"
        fi
        
        if [ ! -f "config/cable.yml" ]; then
            echo "cable.ymlが存在しないため、Solid Cableをインストールします..."
            eval "${env_cmd} bundle exec rails solid_cable:install 2>/dev/null"
            
            # development/test環境でもsolid_cableを使用するように修正
            echo "Rails 8対応のためにSolid Cable設定を修正中..."
            
            cable_yml_content=$(cat config/cable.yml)
            echo "$cable_yml_content" | sed 's/development:\s*\n\s*adapter: async/development:\
  adapter: solid_cable\
  connects_to:\
    database:\
      writing: cable\
  polling_interval: 0.1.seconds\
  message_retention: 1.day/' | sed 's/test:\s*\n\s*adapter: test/test:\
  adapter: solid_cable\
  connects_to:\
    database:\
      writing: cable\
  polling_interval: 0.1.seconds\
  message_retention: 1.day/' > config/cable.yml.tmp && mv config/cable.yml.tmp config/cable.yml
            
            echo "Solid Cable設定をRails 8対応に修正しました"
        else
            echo "cable.ymlが既に存在します"
        fi
            
        # Solid関連データベースのマイグレーション実行
        echo "Solid関連データベースのマイグレーション..."
        
        # キャッシュデータベーススキーマ
        cache_db_file="storage/cache_${RAILS_ENV}.sqlite3"
        if [ -f "$cache_db_file" ]; then
            cache_tables=$(sqlite3 "$cache_db_file" ".tables" 2>/dev/null)
            
            has_schema_migrations=$(echo "$cache_tables" | grep -c "schema_migrations")
            has_app_tables=$(echo "$cache_tables" | grep -c "actors\|objects")
            
            if [ "$has_app_tables" -gt 0 ] && ! echo "$cache_tables" | grep -q "solid_cache_entries"; then
                echo "Cacheデータベースにアプリケーションマイグレーションを適用中..."
                eval "${env_cmd} bundle exec rails db:migrate"
                echo "Cacheデータベースのマイグレーション完了"
            elif ! echo "$cache_tables" | grep -q "solid_cache_entries"; then
                echo "Solid Cacheテーブルを作成中..."
                
                cache_schema_sql='CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS ar_internal_metadata (key varchar NOT NULL PRIMARY KEY, value varchar, created_at datetime(6) NOT NULL, updated_at datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS solid_cache_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  key BLOB NOT NULL,
  value BLOB NOT NULL,
  created_at DATETIME NOT NULL,
  key_hash INTEGER NOT NULL,
  byte_size INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS index_solid_cache_entries_on_key_hash ON solid_cache_entries (key_hash);
CREATE INDEX IF NOT EXISTS index_solid_cache_entries_on_byte_size ON solid_cache_entries (byte_size);
CREATE INDEX IF NOT EXISTS index_solid_cache_entries_on_key_hash_and_byte_size ON solid_cache_entries (key_hash, byte_size);
INSERT OR IGNORE INTO schema_migrations (version) VALUES ('"'"'20240101000001'"'"');'
                
                echo "$cache_schema_sql" | sqlite3 "$cache_db_file" && echo "Solid Cacheテーブルを作成しました" || echo "Solid Cacheテーブル作成に失敗しました"
            else
                echo "Solid Cacheテーブルが存在します"
                
                if [ "$has_schema_migrations" -gt 0 ]; then
                    applied_migrations=$(sqlite3 "$cache_db_file" "SELECT version FROM schema_migrations;" 2>/dev/null | grep -v "20240101000001" | wc -l)
                    
                    if [ "$applied_migrations" -eq 0 ]; then
                        echo "Cacheデータベースにアプリケーションマイグレーションを適用中..."
                        eval "${env_cmd} bundle exec rails db:migrate"
                        echo "Cacheデータベースのマイグレーション完了"
                    fi
                fi
            fi
        fi
        
        # キューデータベーススキーマ
        queue_db_file="storage/queue_${RAILS_ENV}.sqlite3"
        if [ -f "$queue_db_file" ]; then
            queue_tables=$(sqlite3 "$queue_db_file" ".tables" 2>/dev/null)
            if ! echo "$queue_tables" | grep -q "solid_queue_jobs"; then
                echo "Solid Queueテーブルを作成中..."
                if [ -f "db/queue_schema.rb" ]; then
                    eval "${env_cmd} bundle exec rails runner \"
                      begin
                        original_connection = ActiveRecord::Base.connection_db_config.name
                        ActiveRecord::Base.establish_connection(:queue)
                        
                        schema_content = File.read(Rails.root.join('db/queue_schema.rb'))
                        eval(schema_content)
                        
                        puts 'SUCCESS: Solid Queue schema loaded'
                      rescue => e
                        puts 'ERROR: ' + e.message
                        exit 1
                      ensure
                        ActiveRecord::Base.establish_connection(original_connection.to_sym) if original_connection
                      end
                    \"" && echo "Solid Queueスキーマを読み込みました" || echo "Solid Queueスキーマ読み込みに失敗しました"
                else
                    echo "Solid Queueスキーマファイルが見つかりません"
                fi
            else
                echo "Solid Queueテーブルが存在します"
            fi
        fi
        
        # ケーブルデータベーススキーマ
        cable_db_file="storage/cable_${RAILS_ENV}.sqlite3"
        if [ -f "$cable_db_file" ]; then
            cable_tables=$(sqlite3 "$cable_db_file" ".tables" 2>/dev/null)
            if ! echo "$cable_tables" | grep -q "solid_cable_messages"; then
                echo "Solid Cableテーブルを作成中..."
                if [ -f "db/cable_schema.rb" ]; then
                    eval "${env_cmd} bundle exec rails runner \"
                      begin
                        original_connection = ActiveRecord::Base.connection_db_config.name
                        ActiveRecord::Base.establish_connection(:cable)
                        
                        schema_content = File.read(Rails.root.join('db/cable_schema.rb'))
                        eval(schema_content)
                        
                        puts 'SUCCESS: Solid Cable schema loaded'
                      rescue => e
                        puts 'ERROR: ' + e.message
                        exit 1
                      ensure
                        ActiveRecord::Base.establish_connection(original_connection.to_sym) if original_connection
                      end
                    \"" && echo "Solid Cableスキーマを読み込みました" || echo "Solid Cableスキーマ読み込みに失敗しました"
                elif [ -f "db/cable_structure.sql" ]; then
                    sqlite3 "$cable_db_file" < db/cable_structure.sql 2>/dev/null && echo "Solid Cable構造を読み込みました" || echo "Solid Cable構造読み込みに失敗しました"
                else
                    eval "${env_cmd} bundle exec rails runner \"
                      begin
                        ActiveRecord::Base.establish_connection(:cable)
                        ActiveRecord::Base.connection.execute('CREATE TABLE IF NOT EXISTS solid_cable_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, channel VARCHAR NOT NULL, payload TEXT NOT NULL, created_at DATETIME NOT NULL)')
                        ActiveRecord::Base.connection.execute('CREATE INDEX IF NOT EXISTS index_solid_cable_messages_on_channel ON solid_cable_messages (channel)')
                        ActiveRecord::Base.connection.execute('CREATE INDEX IF NOT EXISTS index_solid_cable_messages_on_created_at ON solid_cable_messages (created_at)')
                        puts 'SUCCESS: Solid Cable tables created manually'
                      rescue => e
                        puts 'ERROR: ' + e.message
                        exit 1
                      end
                    \"" && echo "Solid Cableテーブルを手動作成しました" || echo "Solid Cableテーブル作成に失敗しました"
                fi
            else
                echo "Solid Cableテーブルが存在します"
            fi
        fi
        
        # 最終確認
        echo "Solid関連テーブルの最終確認..."
        cache_ok=$(sqlite3 "$cache_db_file" ".tables" 2>/dev/null | grep -c "solid_cache_entries")
        queue_ok=$(sqlite3 "$queue_db_file" ".tables" 2>/dev/null | grep -c "solid_queue_jobs")  
        cable_ok=$(sqlite3 "$cable_db_file" ".tables" 2>/dev/null | grep -c "solid_cable_messages")
        
        if [ "$cache_ok" -gt 0 ] && [ "$queue_ok" -gt 0 ] && [ "$cable_ok" -gt 0 ]; then
            echo "すべてのSolid関連データベースが正常にセットアップされました"
        else
            echo "一部のSolid関連データベースに問題があります (Cache:$cache_ok Queue:$queue_ok Cable:$cable_ok)"
        fi
        
        eval "${env_cmd} bundle exec rails assets:precompile"
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
