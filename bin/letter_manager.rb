#!/usr/bin/env ruby
# frozen_string_literal: true

require 'English'
require 'fileutils'
require 'openssl'
require 'base64'
require 'json'
require 'time'
require 'net/http'
require 'uri'
require 'tempfile'

APP_ROOT = File.expand_path('..', __dir__)

# Actorクラス
class SimpleActor
  attr_accessor :id, :username

  def initialize(id, username)
    @id = id
    @username = username
  end
end

def system!(*)
  system(*, exception: true)
end

def print_header(message)
  puts '========================================'
  puts message
  puts '========================================'
end

def print_success(message)
  puts "✓ #{message}"
end

def print_warning(message)
  puts "⚠️ #{message}"
end

def print_error(message)
  puts "❌ #{message}"
end

def print_info(message)
  puts "ℹ️ #{message}"
end

def docker_environment?
  File.exist?('/.dockerenv')
end

def show_docker_file_help(context = 'ファイル')
  return unless docker_environment?
  
  puts ''
  print_info "🐳 Docker環境: #{context}アクセスのヒント"
  puts '📁 ホストファイルにアクセスするには:'
  puts '   • ボリュームマウント: -v /host/path:/app/mount'
  puts '   • ファイルコピー: docker cp /host/file container:/app/'
  puts '   • コンテナ内パス: /app/mount/filename'
end

def show_logo
  puts ''
  puts ' ██╗      ███████╗ ████████╗ ████████╗ ███████╗ ██████╗'
  puts ' ██║      ██╔════╝ ╚══██╔══╝ ╚══██╔══╝ ██╔════╝ ██╔══██╗'
  puts ' ██║      █████╗      ██║       ██║    █████╗   ██████╔╝'
  puts ' ██║      ██╔══╝      ██║       ██║    ██╔══╝   ██╔══██╗'
  puts ' ███████╗ ███████╗    ██║       ██║    ███████╗ ██║  ██║'
  puts ' ╚══════╝ ╚══════╝    ╚═╝       ╚═╝    ╚══════╝ ╚═╝  ╚═╝'
  puts ''
end

def show_menu
  print_header '統合管理メニュー'
  puts ''
  puts 'サーバ管理:'
  puts '  a) セットアップ'
  puts '  b) サーバ起動・再起動'
  puts '  c) ドメイン設定確認'
  puts '  d) ドメイン切り替え'
  puts ''
  puts 'アカウント管理:'
  puts '  e) アカウント作成・管理'
  puts '  f) パスワード変更'
  puts '  g) アカウント削除'
  puts '  h) OAuthトークン生成'
  puts ''
  puts 'システム管理:'
  puts '  i) VAPIDキー手動生成'
  puts '  j) ローカルの画像をR2に移行する'
  puts '  k) リモート画像キャッシュ管理'
  puts ''
  puts 'データ管理:'
  puts '  l) Mastodonのバックアップからインポート'
  puts '  m) CSVファイルからフォロー処理'
  puts ''
  puts '  x) 終了'
  puts ''
end

# 環境変数読み込み
def load_env_vars
  return {} unless File.exist?('.env')

  env_vars = {}
  File.readlines('.env').each do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    env_vars[key] = value if key && value
  end
  env_vars
end

def run_rails_command(code)
  env_vars = load_env_vars
  rails_env = ENV['RAILS_ENV'] || 'development'
  env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(' ')

  temp_file = "/tmp/rails_temp_#{Random.rand(10_000)}.rb"
  File.write(temp_file, code)

  result = `RAILS_ENV=#{rails_env} #{env_string} bin/rails runner "#{temp_file}" 2>&1`
  FileUtils.rm_f(temp_file)

  # ActivityPub メッセージをフィルタリング
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  filtered_lines.join.strip
ensure
  FileUtils.rm_f(temp_file)
end

def run_rails_command_with_params(code, params = {})
  env_vars = load_env_vars
  rails_env = ENV['RAILS_ENV'] || 'development'
  env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(' ')

  temp_file = "/tmp/rails_temp_#{Random.rand(10_000)}.rb"
  params_file = "/tmp/rails_params_#{Random.rand(10_000)}.json"

  File.write(params_file, JSON.dump(params))

  full_code = <<~RUBY
    require 'json'
    PARAMS = JSON.parse(File.read('#{params_file}'))
    #{code}
  RUBY

  File.write(temp_file, full_code)

  result = `RAILS_ENV=#{rails_env} #{env_string} bin/rails runner "#{temp_file}" 2>/dev/null`

  [temp_file, params_file].each { |f| FileUtils.rm_f(f) }

  result
ensure
  [temp_file, params_file].each { |f| FileUtils.rm_f(f) }
end

# a. セットアップ
def setup_new_installation
  puts ''
  print_header 'セットアップスクリプト'
  print_info "実行時刻: #{Time.now}"
  puts ''

  # 環境ファイルの設定
  print_info '1. 環境ファイルの確認...'
  
  # 実行時のRAILS_ENVを確認
  current_rails_env = ENV['RAILS_ENV'] || 'development'
  is_production = current_rails_env == 'production'
  
  # 環境に応じた設定値を決定
  domain = is_production ? 'your-domain.example.com' : 'localhost'
  protocol = is_production ? 'https' : ''
  queue_in_puma = is_production ? 'false' : 'true'
  
  env_template = <<~ENV
    # ========================================
    # 重要設定
    # ========================================

    # ActivityPub上で使用するドメインを設定します。一度使ったものは再利用できません
    #{is_production ? '# 本番環境では実際のドメインを設定してください' : '# ローカル開発環境の場合は localhost のまま使用できます'}
    ACTIVITYPUB_DOMAIN=#{domain}

    # WebPushを有効化するために必要なVAPID
    #{is_production ? '# 本番環境では必ず rails webpush:generate_vapid_key で生成してください' : '# 開発環境では空欄のまま使用できます（WebPush機能は使用できません）'}
    VAPID_PUBLIC_KEY=
    VAPID_PRIVATE_KEY=

    # ActivityPubではHTTPSでなければ通信できません#{is_production ? '' : '（ローカル開発時は空欄可）'}
    ACTIVITYPUB_PROTOCOL=#{protocol}

    # Rails環境設定
    # development: 開発環境
    # production: 本番環境
    RAILS_ENV=#{current_rails_env}

    # ========================================
    # 開発環境設定
    # ========================================

    # Solid QueueワーカーをPuma内で起動するか
    # true: Puma内でワーカー起動（単一プロセス、開発環境向け）
    # false: 独立プロセスでワーカー起動（本格運用向け、production環境推奨）
    SOLID_QUEUE_IN_PUMA=#{queue_in_puma}

    # ========================================
    # オブジェクトストレージ設定（オプション）
    # ========================================

    # 画像などのファイルをS3互換ストレージに保存する場合は true に設定
    S3_ENABLED=false
    # S3_ENDPOINT=
    # S3_BUCKET=
    # R2_ACCESS_KEY_ID=
    # R2_SECRET_ACCESS_KEY=
    # S3_ALIAS_HOST=
  ENV

  if File.exist?('.env')
    print_success '.envファイルが存在します'

    env_content = File.read('.env')
    missing_keys = []

    %w[ACTIVITYPUB_DOMAIN VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY].each do |key|
      missing_keys << key unless env_content.match?(/^#{key}=.+/)
    end

    if missing_keys.any?
      print_warning "以下の必須設定が不足しています: #{missing_keys.join(', ')}"

      # VAPIDキーが不足している場合は自動生成
      vapid_missing = missing_keys.any? { |key| key.include?('VAPID') }

      if vapid_missing
        puts ''
        print_info 'VAPIDキーが不足しています。自動生成します...'
        generate_vapid_keys
        print_success 'VAPIDキーを自動生成しました'

        # .envファイルを再読み込みして再チェック
        env_content = File.read('.env')
        missing_keys = []
        %w[ACTIVITYPUB_DOMAIN VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY].each do |key|
          missing_keys << key unless env_content.match?(/^#{key}=.+/)
        end
      end

      if missing_keys.any?
        print_warning "まだ不足している設定があります: #{missing_keys.join(', ')}"
        print_info 'サンプル設定を .env.template として作成します'
        File.write('.env.template', env_template)
        puts ''
        print_error '設定完了後、再度このスクリプトを実行してください'
        return
      else
        print_success 'すべての必須設定が完了しました'
      end
    else
      print_success '必須の環境変数が設定されています'
    end
  else
    print_warning '.envファイルが見つかりません。テンプレートを作成します'
    File.write('.env', env_template)
    print_info '.envファイルを作成しました'

    # VAPIDキーを自動生成
    puts ''
    print_info 'VAPIDキーを自動生成します...'
    generate_vapid_keys
    print_success 'VAPIDキーを自動生成しました'

    puts ''
    print_info '残りの設定を編集してください:'
    print_info '  - ACTIVITYPUB_DOMAIN: あなたのドメイン'
    puts ''
    print_error 'ドメイン設定完了後、再度このスクリプトを実行してください'
    return
  end

  # 依存関係のインストール
  print_info '2. 依存関係のインストール...'
  system('bundle check') || system!('bundle install')
  print_success '依存関係をインストールしました'

  # データベースの確認と準備
  print_info '3. データベースの確認と準備...'

  rails_env = ENV['RAILS_ENV'] || 'development'
  db_file = "storage/#{rails_env}.sqlite3"
  if File.exist?(db_file)
    print_success 'データベースファイルが存在します'
  else
    print_warning 'データベースファイルが見つかりません。作成します...'
    begin
      system! "RAILS_ENV=#{rails_env} bin/rails db:create"
      print_success 'データベースを作成しました'
    rescue StandardError => e
      print_error "データベース作成に失敗しました: #{e.message}"
      return
    end
  end

  # マイグレーションの実行
  print_info 'マイグレーションの確認...'

  migrate_output = `RAILS_ENV=#{rails_env} bin/rails db:migrate:status 2>&1`
  if $CHILD_STATUS.success?
    pending_migrations = migrate_output.lines.select { |line| line.include?('down') }

    if pending_migrations.empty?
      print_success 'すべてのマイグレーションが完了しています'
    else
      print_info "#{pending_migrations.count}個の未実行マイグレーションがあります"

      if system("RAILS_ENV=#{rails_env} bin/rails db:migrate 2>/dev/null")
        print_success 'マイグレーションを実行しました'
      else
        print_warning 'マイグレーションでエラーが発生しましたが、続行します'
      end
    end
  else
    print_warning 'マイグレーション状態の確認に失敗しました。スキップします'
  end

  # ログとテンポラリファイルのクリーンアップ
  print_info '4. ログとテンポラリファイルのクリーンアップ...'
  system! "RAILS_ENV=#{rails_env} bin/rails log:clear tmp:clear"
  print_success 'クリーンアップが完了しました'

  # 既存プロセスの確認と停止
  print_info '5. 既存プロセスの確認...'
  rails_running = system("pgrep -f 'rails server' > /dev/null 2>&1")

  # SOLID_QUEUE_IN_PUMAを考慮したプロセス確認
  queue_running = if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
                    false # Puma内で動作するため独立プロセスなし
                  else
                    system("pgrep -f 'solid.*queue' > /dev/null 2>&1")
                  end

  if rails_running || queue_running
    print_warning '既存のプロセスが動作中です。停止します...'
    system("pkill -f 'solid.*queue' 2>/dev/null || true") unless ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    system("pkill -f 'rails server' 2>/dev/null || true")
    system("pkill -f 'puma.*pit1' 2>/dev/null || true")
    sleep 3
    print_success '既存プロセスを停止しました'
  end

  FileUtils.rm_f('tmp/pids/server.pid')
  Dir.glob('tmp/pids/solid_queue*.pid').each { |f| FileUtils.rm_f(f) } unless ENV['SOLID_QUEUE_IN_PUMA'] == 'true'

  answer = safe_gets('サーバを起動しますか？ (y/N): ')

  return unless answer && answer.downcase == 'y'

  # 環境変数の読み込み
  print_info '6. 環境変数の読み込み...'
  env_vars = load_env_vars

  required_vars = %w[ACTIVITYPUB_DOMAIN]
  missing_vars = required_vars.select { |var| env_vars[var].nil? || env_vars[var].empty? }

  if missing_vars.any?
    print_error "必須環境変数が設定されていません: #{missing_vars.join(', ')}"
    return
  end

  print_success '環境変数を読み込みました'
  print_info "ACTIVITYPUB_DOMAIN: #{env_vars['ACTIVITYPUB_DOMAIN']}"
  print_info "ACTIVITYPUB_PROTOCOL: #{env_vars['ACTIVITYPUB_PROTOCOL'] || 'http (default)'}"

  # サーバの起動
  print_info '7. サーバの起動...'

  rails_env = ENV['RAILS_ENV'] || 'development'
  system!("RAILS_ENV=#{rails_env} rails server -b 0.0.0.0 -p 3000 -d")
  print_success 'Railsサーバを起動しました'

  # Solid Queue起動（SOLID_QUEUE_IN_PUMAを考慮）
  if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    print_success 'Solid Queue（Puma内）が設定されています'
  else
    system("RAILS_ENV=#{rails_env} nohup bin/jobs > log/solid_queue.log 2>&1 &")
    print_success 'Solid Queueワーカーを起動しました'
  end

  # 起動確認
  print_info '8. 起動確認中...'
  sleep 5

  server_ok = system('curl -s http://localhost:3000 > /dev/null 2>&1')
  if server_ok
    print_success 'Railsサーバが応答しています'
  else
    print_warning 'Railsサーバの応答確認に失敗しました'
  end

  # Solid Queue確認（SOLID_QUEUE_IN_PUMAを考慮）
  if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    # Puma内でSolid Queueが動作している場合の確認
    queue_ok = check_solid_queue_in_puma_status
    if queue_ok
      print_success 'Solid Queue（Puma内）が動作中です'
    else
      print_warning 'Solid Queue（Puma内）の動作確認に失敗しました'
    end
  else
    # 独立プロセスとしてのSolid Queue確認
    queue_ok = system("pgrep -f 'solid.*queue' > /dev/null 2>&1")
    if queue_ok
      print_success 'Solid Queueワーカーが動作中です'
    else
      print_warning 'Solid Queueワーカーが動作していません'
    end
  end

  # Solid Cache確認
  cache_ok = check_solid_cache_status
  if cache_ok
    print_success 'Solid Cacheが正常に動作しています'
  else
    print_warning 'Solid Cacheの動作確認に失敗しました'
  end

  # Solid Cable確認
  cable_ok = check_solid_cable_status
  if cable_ok
    print_success 'Solid Cableが正常に動作しています'
  else
    print_warning 'Solid Cableの動作確認に失敗しました'
  end

  # 最終結果表示
  puts ''
  print_header 'セットアップ完了'
  print_success 'letter が正常に起動しました'

  domain = env_vars['ACTIVITYPUB_DOMAIN'] || 'localhost'
  protocol = env_vars['ACTIVITYPUB_PROTOCOL'] || 'http'

  print_info 'アクセス情報:'
  puts '  ローカルURL: http://localhost:3000'
  puts "  公開URL: #{protocol}://#{domain}" if domain != 'localhost'
  puts ''
  print_success 'セットアップが正常に完了しました！'
end

# b. サーバ起動・再起動
def cleanup_and_start(show_header = true)
  puts ''
  if show_header
    print_header 'クリーンアップ＆再起動'
    print_info "実行時刻: #{Time.now}"
  end

  # プロセス終了（SOLID_QUEUE_IN_PUMAを考慮）
  print_info '1. 関連プロセスの終了...'
  unless ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    system("pkill -f 'solid.queue' 2>/dev/null || true")
    system("pkill -f 'bin/jobs' 2>/dev/null || true")
  end
  system("pkill -f 'rails server' 2>/dev/null || true")
  system("pkill -f 'puma.*pit1' 2>/dev/null || true")
  sleep 3
  print_success '関連プロセスを終了しました'

  # 環境変数読み込み
  env_vars = load_env_vars
  rails_env = env_vars['RAILS_ENV'] || ENV['RAILS_ENV'] || 'development'

  unless env_vars['ACTIVITYPUB_DOMAIN']
    print_error '.envファイルが見つからないか、ACTIVITYPUB_DOMAINが設定されていません'
    return
  end

  print_success '環境変数を読み込みました'
  print_info "ACTIVITYPUB_DOMAIN: #{env_vars['ACTIVITYPUB_DOMAIN']}"
  print_info "ACTIVITYPUB_PROTOCOL: #{env_vars['ACTIVITYPUB_PROTOCOL']}"
  print_info "RAILS_ENV: #{rails_env}"

  # PIDファイルクリーンアップ
  print_info '3. PIDファイルのクリーンアップ...'
  FileUtils.rm_f('tmp/pids/server.pid')
  Dir.glob('tmp/pids/solid_queue*.pid').each { |f| FileUtils.rm_f(f) } unless ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
  print_success 'PIDファイルをクリーンアップしました'

  # データベースメンテナンス
  print_info '4. データベースのメンテナンス...'
  system("RAILS_ENV=#{rails_env} bin/rails db:migrate 2>/dev/null || true")
  print_success 'データベースメンテナンスが完了しました'

  # キャッシュデータベースのチェックと修復
  cache_db_file = "storage/cache_#{rails_env}.sqlite3"
  if File.exist?(cache_db_file)
    tables = `sqlite3 "#{cache_db_file}" ".tables" 2>/dev/null`.strip
    has_schema_migrations = tables.include?('schema_migrations')
    has_app_tables = tables.include?('actors') || tables.include?('objects') || tables.include?('activities')

    # アプリケーションのテーブルが入っている場合は修復
    if has_app_tables && tables.include?('solid_cache_entries')
      # アプリケーションテーブルとキャッシュテーブルが混在している場合は修復
      print_warning 'キャッシュデータベースに誤ったテーブルが含まれています。修復します...'

      # 現在のマイグレーション状態を保存
      current_migrations = []
      if has_schema_migrations
        current_migrations = `sqlite3 "#{cache_db_file}" "SELECT version FROM schema_migrations;" 2>/dev/null`.strip.split("\n")
      end

      FileUtils.rm_f(cache_db_file)
      require 'sqlite3'
      SQLite3::Database.new(cache_db_file).close

      # Solid Cacheテーブルを作成
      create_cache_table_sql = <<~SQL.squish
        CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY);
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
        INSERT OR IGNORE INTO schema_migrations (version) VALUES ('20240101000001');
      SQL

      system("sqlite3 \"#{cache_db_file}\" <<EOF
#{create_cache_table_sql}
EOF")

      # 保存されたマイグレーション情報を復元
      if current_migrations.any?
        print_info 'マイグレーション情報を復元中...'
        current_migrations.each do |version|
          next if version.empty?

          system("sqlite3 \"#{cache_db_file}\" \"INSERT OR IGNORE INTO schema_migrations (version) VALUES ('#{version}');\"")
        end
        print_success 'マイグレーション情報を復元しました'
      end

      print_success 'キャッシュデータベースを修復しました'
    elsif !tables.include?('solid_cache_entries')
      print_warning 'Solid Cacheテーブルが存在しません。作成します...'
      create_cache_table_sql = <<~SQL.squish
        CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY);
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
        INSERT OR IGNORE INTO schema_migrations (version) VALUES ('20240101000001');
      SQL

      system("sqlite3 \"#{cache_db_file}\" <<EOF
#{create_cache_table_sql}
EOF")
      print_success 'Solid Cacheテーブルを作成しました'
    end
  end

  # Rails サーバ起動
  print_info '5. Railsサーバを起動中...'
  domain = env_vars['ACTIVITYPUB_DOMAIN'] || 'localhost'
  protocol = env_vars['ACTIVITYPUB_PROTOCOL'] || 'http'

  begin
    system!("RAILS_ENV=#{rails_env} ACTIVITYPUB_DOMAIN='#{domain}' ACTIVITYPUB_PROTOCOL='#{protocol}' rails server -b 0.0.0.0 -p 3000 -d")
    print_success 'Railsサーバをデーモンモードで起動しました'
  rescue StandardError => e
    print_error "Railsサーバ起動に失敗しました: #{e.message}"
    return
  end

  # Solid Queue 起動（SOLID_QUEUE_IN_PUMAを考慮）
  print_info '6. Solid Queueワーカーを起動中...'
  if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    print_success 'Solid Queue（Puma内）が設定されています'
  elsif system("RAILS_ENV=#{rails_env} ACTIVITYPUB_DOMAIN='#{domain}' ACTIVITYPUB_PROTOCOL='#{protocol}' nohup bin/jobs > log/solid_queue.log 2>&1 &")
    print_success 'Solid Queueワーカーを起動しました'
  else
    print_warning 'Solid Queueワーカーの起動に失敗しました'
  end

  # 起動確認
  print_info '7. 起動確認を実行中...'
  sleep 5

  if system('curl -s http://localhost:3000 >/dev/null 2>&1')
    print_success 'Railsサーバが応答しています'
  else
    print_error 'Railsサーバが応答していません'
  end

  # Solid Queue確認（SOLID_QUEUE_IN_PUMAを考慮）
  if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
    # Puma内でSolid Queueが動作している場合の確認
    queue_ok = check_solid_queue_in_puma_status
    if queue_ok
      print_success 'Solid Queue（Puma内）が動作中です'
    else
      print_warning 'Solid Queue（Puma内）の動作確認に失敗しました'
    end
  else
    # 独立プロセスとしてのSolid Queue確認
    queue_ok = system("pgrep -f 'solid.*queue' > /dev/null 2>&1")
    if queue_ok
      print_success 'Solid Queueワーカーが動作中です'
    else
      print_warning 'Solid Queueワーカーが動作していません'
    end
  end

  # Solid Cache確認
  cache_ok = check_solid_cache_status
  if cache_ok
    print_success 'Solid Cacheが正常に動作しています'
  else
    print_warning 'Solid Cacheの動作確認に失敗しました'
  end

  # Solid Cable確認
  cable_ok = check_solid_cable_status
  if cable_ok
    print_success 'Solid Cableが正常に動作しています'
  else
    print_warning 'Solid Cableの動作確認に失敗しました'
  end

  puts ''
  print_header '起動完了'
  print_success 'letter が正常に起動しました'

  print_info 'アクセス情報:'
  puts "  サーバURL: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}"
  puts '  ローカルURL: http://localhost:3000'
  puts ''
  print_success 'サーバの起動が正常に完了しました！'
end

# c. ドメイン設定確認
def check_domain_config
  puts ''
  print_header 'ドメイン設定確認'

  # 環境変数確認
  env_vars = load_env_vars
  if env_vars.any?
    print_info '環境設定:'
    puts "  ドメイン: #{env_vars['ACTIVITYPUB_DOMAIN']}"
    puts "  プロトコル: #{env_vars['ACTIVITYPUB_PROTOCOL']}"
    puts "  ベースURL: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}"
  else
    print_warning '.envファイルが見つかりません'
    return
  end

  # サーバ状態チェック
  puts ''
  print_info 'サーバ状態チェック中...'

  rails_running = system("pgrep -f 'rails server' > /dev/null 2>&1")

  if rails_running
    print_success 'サーバ状態: 動作中'

    # HTTP接続テスト
    if env_vars['ACTIVITYPUB_PROTOCOL'] && env_vars['ACTIVITYPUB_DOMAIN']
      server_response = `curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "#{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}" 2>/dev/null`.strip
      puts "  外部URL応答: #{server_response}"
    end

    local_response = `curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost:3000" 2>/dev/null`.strip
    puts "  ローカル応答: #{local_response}"

    # Solid Queue確認（SOLID_QUEUE_IN_PUMAを考慮）
    if ENV['SOLID_QUEUE_IN_PUMA'] == 'true'
      queue_ok = check_solid_queue_in_puma_status
      puts "  Solid Queue（Puma内）: #{queue_ok ? '正常' : 'エラー'}"
    else
      queue_ok = system("pgrep -f 'solid.*queue' > /dev/null 2>&1")
      puts "  Solid Queue: #{queue_ok ? '動作中' : '停止中'}"
    end

    # Solid Cache確認
    cache_ok = check_solid_cache_status
    puts "  Solid Cache: #{cache_ok ? '正常' : 'エラー'}"

    # Solid Cable確認
    cable_ok = check_solid_cable_status
    puts "  Solid Cable: #{cable_ok ? '正常' : 'エラー'}"

    # ローカルユーザ表示
    puts ''
    print_info 'ローカルユーザ:'
    begin
      users_code = 'Actor.where(local: true).pluck(:username).each { |u| puts u }'
      result = run_rails_command(users_code)
      filtered_users = result.strip.lines.reject do |line|
        line.strip.start_with?('ActivityPub configured') ||
          line.strip.empty?
      end
      if filtered_users.empty?
        puts '  ローカルユーザが見つかりません'
      else
        filtered_users.each { |user| puts "  - #{user.strip}" }
      end
    rescue StandardError
      puts '  データベースアクセスエラー'
    end
  else
    print_warning 'サーバ状態: 停止中'
  end
end

# d. ドメイン切り替え
def switch_domain
  puts ''
  print_header 'ドメイン切り替え'

  print '新しいドメインを入力してください: '
  new_domain = gets.chomp

  # 制御文字を除去
  new_domain = new_domain.gsub(/[\x00-\x1F\x7F]/, '')

  if new_domain.empty?
    print_error 'ドメインが入力されていません'
    return
  end

  # URLが入力された場合はドメイン部分を抽出
  new_domain = Regexp.last_match(1) if new_domain =~ /^https?:\/\/(.+)/

  print 'プロトコルを入力してください (https/http, デフォルト: https): '
  new_protocol = gets.chomp

  # 制御文字を除去
  new_protocol = new_protocol.gsub(/[\x00-\x1F\x7F]/, '')
  new_protocol = 'https' if new_protocol.empty?

  # 現在のドメイン取得
  env_vars = load_env_vars
  current_domain = env_vars['ACTIVITYPUB_DOMAIN']

  print_info "新しいドメイン: #{new_domain}"
  print_info "プロトコル: #{new_protocol}"
  print_info "現在のドメイン: #{current_domain}"

  puts ''
  print_warning 'この操作により以下が実行されます:'
  puts '  1. .envファイルの更新'
  puts '  2. 現在のサーバの停止'
  puts '  3. データベース内のActor URLの更新'
  puts '  4. 新しいドメインでのサーバ再起動'
  puts ''
  answer = safe_gets('続行しますか? (y/N): ')

  return unless answer && answer.downcase == 'y'

  # .envファイルの更新
  print_info 'ステップ 1/4: .envファイルの更新...'
  env_content = File.read('.env')
  env_content.gsub!(/^ACTIVITYPUB_DOMAIN=.*/, "ACTIVITYPUB_DOMAIN=#{new_domain}")
  env_content.gsub!(/^ACTIVITYPUB_PROTOCOL=.*/, "ACTIVITYPUB_PROTOCOL=#{new_protocol}")
  File.write('.env', env_content)
  print_success '.envファイルを更新しました'

  # サーバ停止
  print_info 'ステップ 2/4: 現在のサーバを停止中...'
  system("pkill -f 'rails server' 2>/dev/null || true")
  system("pkill -f 'puma' 2>/dev/null || true")
  FileUtils.rm_f('tmp/pids/server.pid')
  print_success 'サーバを停止しました'

  # データベース更新
  print_info 'ステップ 3/4: データベース内のActor URLを更新中...'

  update_code = <<~RUBY
    begin
      new_base_url = "#{new_protocol}://#{new_domain}"
      local_actors = Actor.where(local: true)

      if local_actors.any?
        puts "\#{local_actors.count}個のローカルアクターのドメインを更新します: \#{new_base_url}"
      #{'  '}
        local_actors.each do |actor|
          begin
            actor.update!(
              ap_id: "\#{new_base_url}/users/\#{actor.username}",
              inbox_url: "\#{new_base_url}/users/\#{actor.username}/inbox",
              outbox_url: "\#{new_base_url}/users/\#{actor.username}/outbox",
              followers_url: "\#{new_base_url}/users/\#{actor.username}/followers",
              following_url: "\#{new_base_url}/users/\#{actor.username}/following"
            )
            puts "  ✓ \#{actor.username}を更新しました"
          rescue => e
            puts "  ✗ \#{actor.username}の更新に失敗: \#{e.message}"
            raise e
          end
        end
      #{'  '}
        puts "すべてのローカルアクターの更新が完了しました!"
      else
        puts "ローカルアクターが見つかりません"
      end
    rescue => e
      puts "データベース更新でエラーが発生しました: \#{e.message}"
      puts e.backtrace.first(5).join("\\n")
      exit 1
    end
  RUBY

  env_string = "ACTIVITYPUB_DOMAIN='#{new_domain}' ACTIVITYPUB_PROTOCOL='#{new_protocol}'"
  rails_env = ENV['RAILS_ENV'] || 'development'
  print_info 'データベース更新処理を実行中... (完了までしばらくお待ちください)'
  
  # データベース更新実行
  update_command = "RAILS_ENV=#{rails_env} #{env_string} bin/rails runner \"#{update_code}\""
  result = `#{update_command} 2>&1`
  exit_code = $?.exitstatus
  
  # 結果の表示と検証
  puts result unless result.empty?
  
  if exit_code == 0
    print_success 'データベースのURLを更新しました'
  else
    print_error "データベース更新に失敗しました (終了コード: #{exit_code})"
    print_error 'エラー内容:'
    puts result
    print_error 'ドメイン切り替えを中断します'
    return
  end

  # サーバ再起動
  print_info 'ステップ 4/4: サーバを再起動中...'
  begin
    cleanup_and_start(false)
    print_success 'サーバの再起動が完了しました'
  rescue StandardError => e
    print_error "サーバ再起動でエラーが発生しました: #{e.message}"
    print_warning '手動でサーバを再起動してください: ruby bin/letter_manager.rb'
  end

  puts ''
  print_header 'ドメイン切り替え完了'
  print_success 'ドメイン切り替えが正常に完了しました!'
  print_info '確認情報:'
  puts '  サーバ: http://localhost:3000'
  puts "  ドメイン: #{new_domain}"
  puts "  プロトコル: #{new_protocol}"
end

# e. アカウント作成・管理
def manage_accounts
  puts ''
  print_header 'アカウント管理'

  print_info 'このインスタンスは最大2個のローカルアカウントまで作成できます'
  puts ''

  # 現在のアカウント数を取得
  begin
    account_count_code = 'puts Actor.where(local: true).count'
    result = run_rails_command(account_count_code)
    # ActivityPubメッセージなどの不要な行をフィルタリングして数値を取得
    filtered_lines = result.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') ||
        line.strip.empty?
    end
    account_count = filtered_lines[0]&.strip.to_i
  rescue StandardError
    print_error 'データベースアクセスエラー'
    return
  end

  case account_count
  when 0
    print_info '現在のローカルアカウント数: 0/2'
    puts ''
    print_success '1個目のアカウントを作成します'
    create_account
  when 1
    print_info '現在のローカルアカウント数: 1/2'
    list_accounts_detailed
    puts ''
    print_success '2個目のアカウントを作成できます'
    puts ''
    print '新しいアカウントを作成しますか? (y/N): '
    answer = gets.chomp
    create_account if answer.downcase == 'y'
  when 2
    print_warning '現在のローカルアカウント数: 2/2 (上限に達しています)'
    list_accounts_detailed
    puts ''
    print_info '新しいアカウントを作成するには、既存のアカウントを削除する必要があります'
    puts ''
    puts '選択してください:'
    puts '1) アカウント1を削除して新しいアカウントを作成'
    puts '2) アカウント2を削除して新しいアカウントを作成'
    puts '3) キャンセル'
    puts ''
    print '選択 (1-3): '
    choice = gets.chomp

    case choice
    when '1'
      if delete_account_by_number(1)
        puts ''
        print_info '新しいアカウントを作成します'
        create_account
      end
    when '2'
      if delete_account_by_number(2)
        puts ''
        print_info '新しいアカウントを作成します'
        create_account
      end
    when '3'
      print_info '操作をキャンセルしました'
    else
      print_error '無効な選択です'
    end
  else
    print_error "予期しないアカウント数です: #{account_count}"
  end
end

def list_accounts_detailed
  puts ''
  print_info '現在のローカルアカウント:'
  puts ''

  list_code = <<~RUBY
    accounts = Actor.where(local: true)
    if accounts.any?
      accounts.each_with_index do |account, index|
        puts "\#{index + 1}. ユーザ名: \#{account.username}"
        puts "   表示名: \#{account.display_name || '未設定'}"
        puts "   作成日: \#{account.created_at.strftime('%Y-%m-%d %H:%M')}"
        puts ""
      end
    else
      puts "ローカルアカウントはありません"
    end
  RUBY

  result = run_rails_command(list_code)
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  puts filtered_lines.join unless filtered_lines.empty?
end

def create_account
  puts ''
  print_header '新しいアカウントの作成'
  puts ''

  print_info 'アカウント情報を入力してください:'
  puts ''

  # ユーザ名を取得
  loop do
    username = safe_gets('ユーザ名 (英数字とアンダースコアのみ): ')

    return unless username

    if username.empty?
      print_error 'ユーザ名は必須です'
      next
    end

    unless username.match?(/^[a-zA-Z0-9_]+$/)
      print_error 'ユーザ名は英数字とアンダースコアのみ使用できます'
      print_info "入力された文字: '#{username}'"
      next
    end

    # ユーザ名重複チェック
    check_code = "puts Actor.exists?(username: '#{username}', local: true) ? 'exists' : 'available'"
    result = run_rails_command(check_code)
    filtered_lines = result.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') ||
        line.strip.empty?
    end
    existing_check = filtered_lines[0]&.strip

    if existing_check == 'exists'
      print_error "ユーザ名 '#{username}' は既に存在します"
      next
    end

    @username = username
    break
  end

  # パスワードを取得
  loop do
    password = safe_gets('パスワード (6文字以上): ')

    return unless password

    if password.length < 6
      print_error 'パスワードは6文字以上である必要があります'
      next
    end

    password_confirm = safe_gets('パスワードを再入力: ')

    return unless password_confirm

    if password != password_confirm
      print_error 'パスワードが一致しません'
      next
    end

    @password = password
    break
  end

  # 表示名を取得
  @display_name = safe_gets('表示名 (オプション): ') || ''

  # ノートを取得
  @note = safe_gets('プロフィール (オプション): ') || ''

  puts ''
  print_info '入力内容を確認してください:'
  puts "  ユーザ名: #{@username}"
  puts "  表示名: #{@display_name.empty? ? '未設定' : @display_name}"
  puts "  プロフィール: #{@note.empty? ? '未設定' : @note}"
  puts ''

  answer = safe_gets('この内容でアカウントを作成しますか? (y/N): ')

  return unless answer && answer.downcase == 'y'

  puts ''
  print_info 'アカウントを作成中...'

  # アカウント作成
  creation_code = <<~RUBY
    begin
      actor = Actor.new(
        username: PARAMS['username'],
        password: PARAMS['password'],
        display_name: PARAMS['display_name'],
        note: PARAMS['note'],
        local: true,
        discoverable: true,
        manually_approves_followers: false
      )
    #{'  '}
      if actor.save
        puts 'success'
        puts actor.id
      else
        puts 'error'
        puts actor.errors.full_messages.join(', ')
      end
    rescue => e
      puts 'exception'
      puts e.message
    end
  RUBY

  result = run_rails_command_with_params(creation_code, {
                                           'username' => @username,
                                           'password' => @password,
                                           'display_name' => @display_name,
                                           'note' => @note
                                         })
  # ActivityPubメッセージなどの不要な行をフィルタリング
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  status = filtered_lines[0]&.strip
  detail = filtered_lines[1]&.strip

  if status == 'success'
    env_vars = load_env_vars
    print_success 'アカウントが正常に作成されました!'
    puts ''
    print_info 'アカウント詳細:'
    puts "  ユーザ名: #{@username}"
    puts "  表示名: #{@display_name.empty? ? '未設定' : @display_name}"
    puts "  ActivityPub ID: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}/users/#{@username}"
    puts "  WebFinger: @#{@username}@#{env_vars['ACTIVITYPUB_DOMAIN']}"
  else
    print_error "アカウント作成に失敗しました: #{detail}"
  end
end

# f. パスワード変更
def manage_password
  change_password
end

def change_password
  puts ''
  print_header 'パスワード変更'

  username = safe_gets('ユーザ名を入力してください: ')

  return if username.nil? || username.empty?

  # ユーザ存在チェック
  check_code = "puts Actor.exists?(username: '#{username}', local: true) ? 'exists' : 'not_found'"
  result = run_rails_command(check_code)
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  check_result = filtered_lines[0]&.strip

  if check_result != 'exists'
    print_error "ユーザ '#{username}' が見つかりません"
    return
  end

  # 新しいパスワードを取得
  loop do
    new_password = safe_gets('新しいパスワード (6文字以上): ')

    return unless new_password

    if new_password.length < 6
      print_error 'パスワードは6文字以上である必要があります'
      next
    end

    password_confirm = safe_gets('パスワードを再入力: ')

    return unless password_confirm

    if new_password != password_confirm
      print_error 'パスワードが一致しません'
      next
    end

    # パスワード変更実行
    puts ''
    print_info 'パスワードを変更中...'

    change_code = <<~RUBY
      begin
        actor = Actor.find_by(username: PARAMS['username'], local: true)
        unless actor
          puts 'not_found'
          exit
        end
      #{'  '}
        actor.password = PARAMS['password']
      #{'  '}
        if actor.save
          puts 'success'
          puts "パスワードが正常に変更されました"
        else
          puts 'error'
          puts actor.errors.full_messages.join(', ')
        end
      rescue => e
        puts 'exception'
        puts e.message
      end
    RUBY

    result = run_rails_command_with_params(change_code, { 'username' => username, 'password' => new_password })
    lines = result.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') ||
        line.strip.empty?
    end

    status = lines[0]&.strip
    detail = lines[1]&.strip

    case status
    when 'success'
      print_success detail
    when 'not_found'
      print_error 'ユーザが見つかりません'
    when 'error'
      print_error "パスワード変更に失敗しました: #{detail}"
    when 'exception'
      print_error "エラーが発生しました: #{detail}"
    end

    return
  end
end

# g. アカウント削除
def delete_account
  puts ''
  print_header 'アカウント削除'

  print '削除するアカウントのユーザ名またはIDを入力してください: '
  identifier = gets.chomp

  # 制御文字を除去
  identifier = identifier.gsub(/[\x00-\x1F\x7F]/, '')

  if identifier.empty?
    print_error 'ユーザ名またはIDが入力されていません'
    return
  end

  print_info "アカウントを削除しています: #{identifier}"
  puts ''

  delete_account_by_identifier(identifier)
end

def delete_account_by_number(account_number)
  # アカウント情報取得
  account_info_code = <<~RUBY
    accounts = Actor.where(local: true).order(:created_at)
    if accounts.length >= #{account_number}
      account = accounts[#{account_number - 1}]
      puts account.username
      puts account.display_name || 'なし'
      puts account.id
    else
      puts 'invalid'
    end
  RUBY

  result = run_rails_command(account_info_code)
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end

  return false if filtered_lines[0]&.strip == 'invalid'

  username = filtered_lines[0]&.strip
  display_name = filtered_lines[1]&.strip
  account_id = filtered_lines[2]&.strip

  puts ''
  print_warning '削除対象のアカウント:'
  puts "  ユーザ名: #{username}"
  puts "  表示名: #{display_name}"
  puts ''
  print_error 'この操作は取り消すことができません!'
  puts ''

  print "本当にこのアカウントを削除しますか? 'DELETE' と入力してください: "
  confirm = gets.chomp

  return false unless confirm == 'DELETE'

  puts ''
  print_info 'アカウントを削除中...'

  # 直接削除処理を実行（確認は既に完了）
  perform_account_deletion(account_id)
end

def perform_account_deletion(identifier)
  deletion_code = <<~RUBY
    begin
      # IDまたはユーザ名でアクターを検索
      if '#{identifier}'.match?(/^\\d+$/)
        actor = Actor.find_by(id: '#{identifier}')
      else
        actor = Actor.find_by(username: '#{identifier}', local: true)
      end
    #{'  '}
      unless actor
        puts 'not_found'
        exit
      end
    #{'  '}
      actor_id = actor.id
      username = actor.username
    #{'  '}
      # 直接SQL削除で依存レコードを削除
      ActiveRecord::Base.connection.execute("DELETE FROM web_push_subscriptions WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM notifications WHERE account_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM notifications WHERE from_account_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM bookmarks WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM favourites WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM reblogs WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM mentions WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM media_attachments WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM follows WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM follows WHERE target_actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM objects WHERE actor_id = \#{actor_id}")
      ActiveRecord::Base.connection.execute("DELETE FROM activities WHERE actor_id = \#{actor_id}")
    #{'  '}
      # OAuthトークンも削除
      begin
        Doorkeeper::AccessToken.where(resource_owner_id: actor_id).delete_all
        Doorkeeper::AccessGrant.where(resource_owner_id: actor_id).delete_all
      rescue
        # Doorkeeperテーブルがない場合はスキップ
      end
    #{'  '}
      # 最後にアカウント削除
      ActiveRecord::Base.connection.execute("DELETE FROM actors WHERE id = \#{actor_id}")
    #{'  '}
      puts 'success'
      puts "アカウント '\#{username}' とすべての関連レコードが正常に削除されました"
    #{'  '}
    rescue => e
      puts 'error'
      puts e.message
    end
  RUBY

  result = run_rails_command(deletion_code)
  filtered_lines = result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  result_status = filtered_lines[0]&.strip

  if result_status == 'success'
    print_success filtered_lines[1]&.strip

    # 残りアカウント数表示
    remaining_code = 'puts Actor.where(local: true).count'
    remaining_result = run_rails_command(remaining_code)
    remaining_lines = remaining_result.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') ||
        line.strip.empty?
    end
    remaining_count = remaining_lines[0]&.strip
    print_info "残りのローカルアカウント数: #{remaining_count}"
    true
  else
    detail = filtered_lines[1..]&.join("\n")
    print_error "削除に失敗しました: #{detail}"
    false
  end
end

def delete_account_by_identifier(identifier)
  # まずアカウント情報を取得
  account_info_code = <<~RUBY
    begin
      # IDまたはユーザ名でアクターを検索
      if '#{identifier}'.match?(/^\\d+$/)
        actor = Actor.find_by(id: '#{identifier}')
      else
        actor = Actor.find_by(username: '#{identifier}', local: true)
      end
    #{'  '}
      unless actor
        puts 'not_found'
        puts 'アカウントが見つかりません'
        exit
      end
    #{'  '}
      puts 'found'
      puts "ID: \#{actor.id}"
      puts "ユーザ名: \#{actor.username}"
      puts "表示名: \#{actor.display_name || '未設定'}"
      puts "作成日: \#{actor.created_at.strftime('%Y-%m-%d %H:%M')}"
    #{'  '}
      # 投稿数などの統計情報
      posts_count = ActivityPubObject.where(actor_id: actor.id, object_type: 'Note').count
      following_count = Follow.where(actor_id: actor.id).count
      followers_count = Follow.where(target_actor_id: actor.id).count
    #{'  '}
      puts "投稿数: \#{posts_count}"
      puts "フォロー数: \#{following_count}"
      puts "フォロワー数: \#{followers_count}"
    #{'  '}
    rescue => e
      puts 'error'
      puts e.message
    end
  RUBY

  info_result = run_rails_command(account_info_code)
  info_lines = info_result.strip.lines.reject do |line|
    line.strip.start_with?('ActivityPub configured') ||
      line.strip.empty?
  end
  status = info_lines[0]&.strip

  case status
  when 'not_found'
    detail = info_lines[1]&.strip
    print_error detail

    print_info '既存のローカルユーザ一覧:'
    list_code = <<~RUBY
      actors = Actor.where(local: true)
      if actors.any?
        actors.each { |a| puts "  - ID: \#{a.id}, ユーザ名: \#{a.username} (\#{a.display_name || '表示名未設定'})" }
      else
        puts '  ローカルユーザがありません。'
      end
    RUBY

    local_users = run_rails_command(list_code)
    filtered_list = local_users.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') ||
        line.strip.empty?
    end
    puts filtered_list.join unless filtered_list.empty?
    false
  when 'found'
    puts ''
    print_warning '削除対象のアカウント詳細:'
    info_lines[1..].each { |line| puts "  #{line.strip}" }
    puts ''

    print_error '⚠️ 重要な警告 ⚠️'
    puts 'この操作により以下のデータが完全に削除されます:'
    puts '  • アカウント情報（プロフィール、設定等）'
    puts '  • 投稿したすべての内容'
    puts '  • フォロー・フォロワー関係'
    puts '  • お気に入り、ブックマーク'
    puts '  • 通知履歴'
    puts '  • OAuthトークン'
    puts '  • その他すべての関連データ'
    puts ''
    print_error 'この操作は取り消すことができません！'
    puts ''

    # 最終確認
    answer1 = safe_gets('本当にこのアカウントを削除しますか？ (yes/no): ')
    return false unless answer1&.downcase == 'yes'

    puts ''
    print_warning '最終確認です。'
    answer2 = safe_gets("確実に削除を実行するため 'DELETE' と正確に入力してください: ")
    return false unless answer2 == 'DELETE'

    puts ''
    print_info 'アカウントを削除しています...'

    # 実際の削除処理
    deletion_code = <<~RUBY
      begin
        # アカウント再取得
        if '#{identifier}'.match?(/^\\d+$/)
          actor = Actor.find_by(id: '#{identifier}')
        else
          actor = Actor.find_by(username: '#{identifier}', local: true)
        end
      #{'  '}
        unless actor
          puts 'not_found'
          exit
        end
      #{'  '}
        actor_id = actor.id
        username = actor.username
      #{'  '}
        # 直接SQL削除で依存レコードを削除
        ActiveRecord::Base.connection.execute("DELETE FROM web_push_subscriptions WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM notifications WHERE account_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM notifications WHERE from_account_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM bookmarks WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM favourites WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM reblogs WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM mentions WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM media_attachments WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM follows WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM follows WHERE target_actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM objects WHERE actor_id = \#{actor_id}")
        ActiveRecord::Base.connection.execute("DELETE FROM activities WHERE actor_id = \#{actor_id}")
      #{'  '}
        # OAuthトークンも削除
        begin
          Doorkeeper::AccessToken.where(resource_owner_id: actor_id).delete_all
          Doorkeeper::AccessGrant.where(resource_owner_id: actor_id).delete_all
        rescue
          # Doorkeeperテーブルがない場合はスキップ
        end
      #{'  '}
        # 最後にアカウント削除
        ActiveRecord::Base.connection.execute("DELETE FROM actors WHERE id = \#{actor_id}")
      #{'  '}
        puts 'success'
        puts "アカウント '\#{username}' とすべての関連レコードが正常に削除されました"
      #{'  '}
      rescue => e
        puts 'error'
        puts e.message
      end
    RUBY

    result = run_rails_command(deletion_code)
    result_lines = result.strip.lines
    result_status = result_lines[0]&.strip

    if result_status == 'success'
      print_success result_lines[1]&.strip

      # 残りアカウント数表示
      remaining_code = 'puts Actor.where(local: true).count'
      remaining_count = run_rails_command(remaining_code).strip
      print_info "残りのローカルアカウント数: #{remaining_count}"
      true
    else
      detail = result_lines[1..]&.join("\n")
      print_error "削除に失敗しました: #{detail}"
      false
    end
  when 'error'
    detail = info_lines[1..]&.join("\n")
    print_error 'アカウント情報取得中にエラーが発生しました:'
    puts detail
    false
  else
    print_error '予期しない結果:'
    puts info_result
    false
  end
end

# i. OAuthトークン生成
def create_oauth_token
  puts ''
  print_header 'OAuth トークン生成'
  puts ''

  print_info 'このスクリプトはAPIアクセス用のOAuthトークンを生成します'
  puts ''

  # ユーザ名入力
  loop do
    print 'ユーザ名を入力してください: '
    username = gets.chomp

    # 制御文字を除去
    username = username.gsub(/[\x00-\x1F\x7F]/, '')

    if username.empty?
      print_error 'ユーザ名は必須です'
      next
    end

    unless username.match?(/^[a-zA-Z0-9_]+$/)
      print_error 'ユーザ名は英数字とアンダースコアのみ使用できます'
      print_info "入力された文字: '#{username}'"
      next
    end

    # ユーザ存在チェック
    user_check_code = "puts Actor.exists?(username: '#{username}', local: true) ? 'exists' : 'not_found'"
    user_check = run_rails_command(user_check_code).strip

    if user_check == 'not_found'
      print_error "ユーザ '#{username}' が見つかりません"
      print_info '既存のローカルユーザを確認してください'
      puts ''
      print_info '既存のローカルユーザ一覧:'

      users_code = <<~RUBY
        actors = Actor.where(local: true)
        if actors.any?
          actors.each { |a| puts "  - \#{a.username} (\#{a.display_name || 'No display name'})" }
        else
          puts '  ローカルユーザがありません。まずアカウントを作成してください。'
        end
      RUBY

      local_users = run_rails_command(users_code)
      puts local_users
      puts ''
      next
    end

    @token_username = username
    break
  end

  puts ''
  print_info "ユーザ '#{@token_username}' 用のOAuthトークンを生成中..."

  # トークン生成
  token_code = <<~RUBY
    username = '#{@token_username}'

    begin
      actor = Actor.find_by(username: username, local: true)
      unless actor
        puts "error|ユーザ '\#{username}' が見つかりません"
        exit 1
      end

      existing_app = Doorkeeper::Application.find_by(uid: "letter_client_\#{username}")
      existing_token = nil
    #{'  '}
      if existing_app
        existing_token = Doorkeeper::AccessToken.find_by(
          application: existing_app,
          resource_owner_id: actor.id,
          revoked_at: nil
        )
      end

      if existing_token
        puts "exists|既存のOAuthトークンが見つかりました"
        puts "app_name|\#{existing_app.name}"
        puts "client_id|\#{existing_app.uid}"
        puts "client_secret|\#{existing_app.secret}"
        puts "token|\#{existing_token.token}"
        puts "scopes|\#{existing_token.scopes}"
        puts "username|\#{actor.username}"
        puts "domain|\#{ENV['ACTIVITYPUB_DOMAIN']}"
        puts "protocol|\#{ENV['ACTIVITYPUB_PROTOCOL']}"
        puts "created_at|\#{existing_token.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
      else
        app = Doorkeeper::Application.find_or_create_by(uid: "letter_client_\#{username}") do |a|
          a.name = "letter API Client (\#{username})"
          a.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
          a.scopes = "read write follow push"
        end

        token = Doorkeeper::AccessToken.create!(
          application: app,
          resource_owner_id: actor.id,
          scopes: "read write follow push"
        )

        puts "success|OAuth トークンが正常に作成されました！"
        puts "app_name|\#{app.name}"
        puts "client_id|\#{app.uid}"
        puts "client_secret|\#{app.secret}"
        puts "token|\#{token.token}"
        puts "scopes|\#{token.scopes}"
        puts "username|\#{actor.username}"
        puts "domain|\#{ENV['ACTIVITYPUB_DOMAIN']}"
        puts "protocol|\#{ENV['ACTIVITYPUB_PROTOCOL']}"
        puts "created_at|\#{token.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
      end

    rescue => e
      puts "error|トークン作成に失敗しました: \#{e.message}"
      exit 1
    end
  RUBY

  result = run_rails_command(token_code)
  puts ''

  # 結果解析
  lines = result.strip.lines
  status_line = lines.find { |l| l.match?(/^(success|error|exists)\|/) }
  return unless status_line

  status, message = status_line.split('|', 2)

  token_data = {}
  lines.each do |line|
    if line.include?('|')
      key, value = line.strip.split('|', 2)
      token_data[key] = value
    end
  end

  if %w[success exists].include?(status)
    if status == 'success'
      print_success message
    else
      print_warning message
    end

    puts ''
    print_header '生成されたOAuthトークン情報'
    puts ''
    print_info 'アプリケーション詳細:'
    puts "  名前: #{token_data['app_name']}"
    puts "  クライアントID: #{token_data['client_id']}"
    puts "  クライアントシークレット: #{token_data['client_secret']}"
    puts ''
    print_info '🔑 アクセストークン（重要！）:'
    puts "  #{token_data['token']}"
    puts ''
    print_info 'トークン詳細:'
    puts "  スコープ: #{token_data['scopes']}"
    puts "  ユーザ: #{token_data['username']}"
    puts "  作成日時: #{token_data['created_at']}"
    puts ''
    print_header 'API使用例'
    puts ''
    print_info '📋 よく使用されるAPIコマンド（コピーして使用してください）:'
    puts ''
    puts '# アカウント情報確認'
    puts "curl -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/accounts/verify_credentials\""
    puts ''
    puts '# 投稿作成'
    puts 'curl -X POST \\'
    puts "     -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts '     -H "Content-Type: application/json" \\'
    puts "     -d '{\"status\":\"Hello from API!\",\"visibility\":\"public\"}' \\"
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/statuses\""
    puts ''
    puts '# アバター画像設定'
    puts 'curl -X PATCH \\'
    puts "     -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts '     -F "avatar=@/path/to/image.png" \\'
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/accounts/update_credentials\""
    puts ''
    print_warning '⚠️ このトークンは秘密情報です。安全に保管してください。'
    puts ''
    print_success 'OAuthトークンの生成が完了しました！'
  else
    print_error message
  end
end

# j. VAPIDキー生成
def generate_vapid_keys
  puts ''
  print_header 'VAPID キーペア生成'
  puts ''

  begin
    # opensslコマンドを使用してVAPIDキーを生成
    print_info '1. 秘密鍵を生成中...'

    # 一時ファイル名
    private_key_file = "/tmp/vapid_private_key_#{Random.rand(10_000)}.pem"
    public_key_file = "/tmp/vapid_public_key_#{Random.rand(10_000)}.pem"

    # 秘密鍵を生成 (P-256楕円曲線)
    raise '秘密鍵の生成に失敗しました' unless system("openssl ecparam -genkey -name prime256v1 -noout -out #{private_key_file} 2>/dev/null")

    # 公開鍵を生成
    print_info '2. 公開鍵を生成中...'
    raise '公開鍵の生成に失敗しました' unless system("openssl ec -in #{private_key_file} -pubout -out #{public_key_file} 2>/dev/null")

    # Base64エンコード（URLセーフ）でキーを抽出
    print_info '3. キーをBase64エンコード中...'

    # Rubyの標準ライブラリを使用してより確実にキーを抽出
    require 'openssl'

    # PEMファイルから秘密鍵を読み込み
    private_key_pem = File.read(private_key_file)
    private_key = OpenSSL::PKey::EC.new(private_key_pem)

    # 秘密鍵のバイナリデータを取得（32バイト）
    private_key_bn = private_key.private_key
    private_key_bytes = private_key_bn.to_s(2).rjust(32, "\x00")
    private_key_b64 = Base64.urlsafe_encode64(private_key_bytes).delete('=')

    # 公開鍵のバイナリデータを取得（64バイト、0x04プレフィックスを除く）
    public_key_point = private_key.public_key
    public_key_bytes = public_key_point.to_bn.to_s(2)[1..] # 最初の0x04バイトを除去
    public_key_b64 = Base64.urlsafe_encode64(public_key_bytes).delete('=')

    # 一時ファイルを削除
    FileUtils.rm_f(private_key_file)
    FileUtils.rm_f(public_key_file)

    raise 'キーの抽出に失敗しました' if private_key_b64.empty? || public_key_b64.empty?

    puts ''
    print_header '生成されたVAPIDキーペア'
    puts "VAPID_PUBLIC_KEY=#{public_key_b64}"
    puts "VAPID_PRIVATE_KEY=#{private_key_b64}"
    puts ''

    print_info '.envファイルへの追加'
    puts '以下の行を .env ファイルに追加または更新してください：'
    puts ''
    puts "VAPID_PUBLIC_KEY=#{public_key_b64}"
    puts "VAPID_PRIVATE_KEY=#{private_key_b64}"
    puts ''

    # 既存の.envファイルがある場合、更新を提案
    if File.exist?('.env')
      response = safe_gets('既存の.envファイルを更新しますか？ (y/N): ')

      if response && response.downcase == 'y'
        # バックアップを作成
        FileUtils.cp('.env', '.env.backup')
        print_info '.envファイルのバックアップを作成しました: .env.backup'

        # 既存のVAPIDキーを削除して新しいキーを追加
        env_content = File.read('.env')
        env_content.gsub!(/^VAPID_PUBLIC_KEY=.*\n?/, '')
        env_content.gsub!(/^VAPID_PRIVATE_KEY=.*\n?/, '')

        # ファイルの最後に新しいキーを追加
        env_content = "#{env_content.rstrip}\n"
        env_content += "VAPID_PUBLIC_KEY=#{public_key_b64}\n"
        env_content += "VAPID_PRIVATE_KEY=#{private_key_b64}\n"

        File.write('.env', env_content)
        print_success '.envファイルを更新しました'
      end
    end

    puts ''
    print_header '注意事項'
    puts '- VAPIDキーを変更すると、既存のプッシュ通知サブスクリプションは無効になります'
    puts '- サーバを再起動して新しいキーを適用してください'
    puts '- これらのキーは安全に保管してください'
    puts ''
    print_success 'VAPIDキーの生成が完了しました！'
  rescue StandardError => e
    print_error "VAPIDキー生成に失敗しました: #{e.message}"
    print_info "詳細: #{e.backtrace.first}" if e.backtrace

    # 一時ファイルをクリーンアップ
    [private_key_file, public_key_file].each do |file|
      File.delete(file) if file && File.exist?(file)
    end
  end
end

# k. Cloudflare R2 移行
def migrate_to_r2
  puts ''
  print_header 'Cloudflare R2 移行'
  puts ''

  env_vars = load_env_vars

  # R2が有効かチェック
  unless env_vars['S3_ENABLED'] == 'true'
    print_error 'Cloudflare R2が無効になっています'
    print_info '移行を実行するには、.envファイルでS3_ENABLED=trueに設定してください'
    return
  end

  # 必要なR2設定をチェック
  missing_config = []
  %w[S3_ENDPOINT S3_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY].each do |key|
    missing_config << key if env_vars[key].nil? || env_vars[key].empty?
  end

  if missing_config.any?
    print_error "以下の設定が不足しています: #{missing_config.join(', ')}"
    print_info '設定を確認してから再度実行してください'
    return
  end

  print_success 'Cloudflare R2設定確認完了'
  puts ''
  print_info "エンドポイント: #{env_vars['S3_ENDPOINT']}"
  print_info "バケット: #{env_vars['S3_BUCKET']}"
  puts ''

  # 移行統計を取得
  print_info '現在のファイル状況を確認中...'

  stats_code = <<~RUBY
    total_local = ActiveStorage::Blob.where(service_name: ['local', nil]).count
    total_r2 = ActiveStorage::Blob.where(service_name: 'cloudflare_r2').count

    puts "total_local|\#{total_local}"
    puts "total_r2|\#{total_r2}"
  RUBY

  result = run_rails_command(stats_code)

  local_total = result.lines.find { |l| l.start_with?('total_local|') }&.split('|', 2)&.last&.strip.to_i
  r2_total = result.lines.find { |l| l.start_with?('total_r2|') }&.split('|', 2)&.last&.strip.to_i

  puts ''
  print_info 'ファイル状況:'
  puts "  ローカル合計: #{local_total}"
  puts "  R2合計: #{r2_total}"
  puts ''

  if local_total.zero?
    print_success '移行対象のローカルファイルはありません'
    return
  end

  # 移行を確認
  print 'これらのファイルをCloudflare R2に移行しますか？ (y/N): '
  confirmation = gets.chomp

  return unless confirmation.downcase == 'y'

  puts ''
  print 'バッチサイズを入力してください (10-200, デフォルト: 50): '
  batch_size = gets.chomp
  batch_size = batch_size.empty? ? 50 : batch_size.to_i

  if batch_size < 10 || batch_size > 200
    print_error 'バッチサイズは10から200の間で指定してください'
    return
  end

  puts ''
  print_info "バッチサイズ: #{batch_size} でR2への移行を開始します..."

  # 移行を実行
  migration_code = <<~RUBY
    begin
      MigrateToR2Job.perform_now(batch_size: #{batch_size})
      puts 'success|移行が正常に完了しました'
    rescue => e
      puts "error|移行に失敗しました: \#{e.message}"
    end
  RUBY

  migration_result = run_rails_command(migration_code)
  status_line = migration_result.lines.find { |l| l.include?('|') }

  if status_line
    status, message = status_line.strip.split('|', 2)

    puts ''
    if status == 'success'
      print_success message

      # 最終統計を取得
      final_result = run_rails_command(stats_code)
      final_local = final_result.lines.find { |l| l.start_with?('total_local|') }&.split('|', 2)&.last&.strip.to_i
      final_r2 = final_result.lines.find { |l| l.start_with?('total_r2|') }&.split('|', 2)&.last&.strip.to_i

      puts ''
      print_info '移行後の状況:'
      puts "  ローカル: #{final_local}"
      puts "  R2: #{final_r2}"
    else
      print_error message
    end
  else
    print_error '移行結果の解析に失敗しました'
  end

  puts ''
  print_header 'Cloudflare R2 移行完了'
end

# l. リモート画像キャッシュ管理
def manage_remote_image_cache
  puts ''
  print_header 'リモート画像キャッシュ管理'
  puts ''

  # 現在の統計を取得
  print_info 'キャッシュ統計を取得中...'

  stats_code = <<~RUBY
    # リモート画像の統計
    total_remote = MediaAttachment.joins(:actor)
                                 .where(actors: { local: false })
                                 .where.not(remote_url: nil)
                                 .count

    cached_remote = MediaAttachment.joins(:actor)
                                  .where(actors: { local: false })
                                  .joins('INNER JOIN active_storage_attachments asa ON asa.record_id = media_attachments.id')
                                  .count

    # Solid Cacheエントリ数
    cache_entries = Rails.cache.instance_variable_get(:@data)&.keys&.count { |k| k.to_s.start_with?('remote_image:') } rescue 0

    # Active Storage統計
    total_blobs = ActiveStorage::Blob.where('key LIKE ?', 'img/%').count
    total_blob_size = ActiveStorage::Blob.where('key LIKE ?', 'img/%').sum(:byte_size)

    puts "total_remote|\#{total_remote}"
    puts "cached_remote|\#{cached_remote}"
    puts "cache_entries|\#{cache_entries}"
    puts "total_blobs|\#{total_blobs}"
    puts "total_blob_size|\#{total_blob_size}"
  RUBY

  result = run_rails_command(stats_code)

  total_remote = result.lines.find { |l| l.start_with?('total_remote|') }&.split('|', 2)&.last&.strip.to_i
  cached_remote = result.lines.find { |l| l.start_with?('cached_remote|') }&.split('|', 2)&.last&.strip.to_i
  cache_entries = result.lines.find { |l| l.start_with?('cache_entries|') }&.split('|', 2)&.last&.strip.to_i
  total_blobs = result.lines.find { |l| l.start_with?('total_blobs|') }&.split('|', 2)&.last&.strip.to_i
  total_blob_size = result.lines.find { |l| l.start_with?('total_blob_size|') }&.split('|', 2)&.last&.strip.to_i

  puts ''
  print_info 'リモート画像キャッシュ統計:'
  puts "  リモート画像合計: #{total_remote}"
  puts "  キャッシュ済み: #{cached_remote} (#{cached_remote.positive? ? ((cached_remote.to_f / total_remote) * 100).round(1) : 0}%)"
  puts "  キャッシュエントリ: #{cache_entries}"
  puts "  ストレージ使用量: #{(total_blob_size / 1024.0 / 1024.0).round(2)} MB (#{total_blobs}ファイル)"
  puts ''

  puts '選択してください:'
  puts '1) 最近のリモート画像をキャッシュ (バッチ処理)'
  puts '2) 特定期間の画像をキャッシュ'
  puts '3) キャッシュクリーンアップを実行'
  puts '4) キャッシュ統計の詳細表示'
  puts '5) 戻る'
  puts ''

  choice = safe_gets('選択 (1-5): ')

  case choice
  when '1'
    batch_cache_recent_images
  when '2'
    batch_cache_period_images
  when '3'
    run_cache_cleanup
  when '4'
    show_cache_details
  when '5'
    nil
  else
    print_error '無効な選択です'
  end
end

def batch_cache_recent_images
  puts ''
  print_info '最近のリモート画像をキャッシュします'

  days = safe_gets('過去何日分をキャッシュしますか？ (デフォルト: 7): ')
  days = days.empty? ? 7 : days.to_i

  batch_size = safe_gets('バッチサイズ (10-100, デフォルト: 50): ')
  batch_size = batch_size.empty? ? 50 : batch_size.to_i

  if batch_size < 10 || batch_size > 100
    print_error 'バッチサイズは10から100の間で指定してください'
    return
  end

  puts ''
  print_info "#{days}日以内のリモート画像を#{batch_size}件ずつキャッシュします..."

  cache_code = <<~RUBY
    require 'time'

    target_date = #{days}.days.ago

    # キャッシュ対象の画像を検索
    images_to_cache = MediaAttachment.joins(:actor)
                                    .where(actors: { local: false })
                                    .where.not(remote_url: nil)
                                    .where('media_attachments.created_at >= ?', target_date)
                                    .where.not(id: MediaAttachment.joins('INNER JOIN active_storage_attachments asa ON asa.record_id = media_attachments.id').select(:id))

    total_count = images_to_cache.count
    puts "対象画像: \#{total_count}件"

    if total_count == 0
      puts "キャッシュ対象の画像がありません"
      exit
    end

    cached_count = 0
    failed_count = 0

    images_to_cache.find_each(batch_size: #{batch_size}) do |media|
      begin
        RemoteImageCacheJob.perform_later(media.id)
        cached_count += 1
    #{'    '}
        if cached_count % 10 == 0
          puts "進捗: \#{cached_count}/\#{total_count} 件をキューに追加"
        end
      rescue => e
        failed_count += 1
        puts "エラー: Media \#{media.id} - \#{e.message}"
      end
    end

    puts "success|\#{cached_count}件のキャッシュジョブをキューに追加しました"
    puts "failed|\#{failed_count}"
  RUBY

  result = run_rails_command(cache_code)
  puts result

  status_line = result.lines.find { |l| l.start_with?('success|') }
  if status_line
    message = status_line.split('|', 2).last.strip
    print_success message
    print_info 'バックグラウンドでキャッシュ処理が実行されます'
  else
    print_error 'キャッシュジョブの開始に失敗しました'
  end
end

def batch_cache_period_images
  puts ''
  print_info '特定期間のリモート画像をキャッシュします'

  start_date = safe_gets('開始日 (YYYY-MM-DD): ')
  end_date = safe_gets('終了日 (YYYY-MM-DD, 省略時は今日): ')
  end_date = Date.current.to_s if end_date.empty?

  begin
    start_date = Date.parse(start_date)
    end_date = Date.parse(end_date)
  rescue ArgumentError
    print_error '無効な日付形式です'
    return
  end

  batch_size = safe_gets('バッチサイズ (10-100, デフォルト: 50): ')
  batch_size = batch_size.empty? ? 50 : batch_size.to_i

  puts ''
  print_info "#{start_date} から #{end_date} までのリモート画像をキャッシュします..."

  # 同様のキャッシュ処理（日付範囲指定版）
  cache_code = <<~RUBY
    start_date = Date.parse('#{start_date}')
    end_date = Date.parse('#{end_date}')

    images_to_cache = MediaAttachment.joins(:actor)
                                    .where(actors: { local: false })
                                    .where.not(remote_url: nil)
                                    .where('media_attachments.created_at >= ? AND media_attachments.created_at <= ?', start_date, end_date.end_of_day)
                                    .where.not(id: MediaAttachment.joins('INNER JOIN active_storage_attachments asa ON asa.record_id = media_attachments.id').select(:id))

    total_count = images_to_cache.count
    puts "対象画像: \#{total_count}件"

    cached_count = 0
    images_to_cache.find_each(batch_size: #{batch_size}) do |media|
      RemoteImageCacheJob.perform_later(media.id)
      cached_count += 1
    #{'  '}
      if cached_count % 10 == 0
        puts "進捗: \#{cached_count}/\#{total_count} 件をキューに追加"
      end
    end

    puts "success|\#{cached_count}件のキャッシュジョブをキューに追加しました"
  RUBY

  result = run_rails_command(cache_code)
  puts result

  status_line = result.lines.find { |l| l.start_with?('success|') }
  return unless status_line

  message = status_line.split('|', 2).last.strip
  print_success message
end

def run_cache_cleanup
  puts ''
  print_warning '期限切れキャッシュとファイルをクリーンアップします'
  puts ''

  answer = safe_gets('クリーンアップを実行しますか？ (y/N): ')
  return unless answer&.downcase == 'y'

  print_info 'キャッシュクリーンアップを実行中...'

  cleanup_code = <<~RUBY
    begin
      CacheCleanupJob.perform_now
      puts "success|キャッシュクリーンアップが完了しました"
    rescue => e
      puts "error|クリーンアップに失敗しました: \#{e.message}"
    end
  RUBY

  result = run_rails_command(cleanup_code)
  status_line = result.lines.find { |l| l.include?('|') }

  return unless status_line

  status, message = status_line.strip.split('|', 2)
  if status == 'success'
    print_success message
  else
    print_error message
  end
end

def show_cache_details
  puts ''
  print_header 'キャッシュ詳細統計'

  details_code = <<~RUBY
    # 詳細統計を取得
    puts "=== リモート画像統計 ==="

    # 日付別統計
    recent_stats = MediaAttachment.joins(:actor)
                                 .where(actors: { local: false })
                                 .where.not(remote_url: nil)
                                 .where('media_attachments.created_at >= ?', 30.days.ago)
                                 .group('DATE(media_attachments.created_at)')
                                 .count

    puts "過去30日の日別リモート画像数:"
    recent_stats.sort.last(7).each do |date, count|
      puts "  \#{date}: \#{count}件"
    end

    puts ""
    puts "=== キャッシュ統計 ==="

    # ドメイン別統計
    domain_stats = MediaAttachment.joins(:actor)
                                 .joins('INNER JOIN active_storage_attachments asa ON asa.record_id = media_attachments.id')
                                 .where(actors: { local: false })
                                 .group('actors.domain')
                                 .count

    puts "ドメイン別キャッシュ数 (上位10):"
    domain_stats.sort_by { |_, count| -count }.first(10).each do |domain, count|
      puts "  \#{domain}: \#{count}件"
    end

    puts ""
    puts "=== ストレージ使用量 ==="

    size_stats = ActiveStorage::Blob.where('key LIKE ?', 'img/%')
                                   .group('DATE(created_at)')
                                   .sum(:byte_size)

    puts "日別ストレージ使用量 (過去7日):"
    size_stats.sort.last(7).each do |date, size|
      puts "  \#{date}: \#{(size / 1024.0 / 1024.0).round(2)} MB"
    end
  RUBY

  result = run_rails_command(details_code)
  puts result
end

def check_solid_cache_status
  # Solid Cacheの動作確認（テーブル存在確認のみ）
  cache_check_code = <<~RUBY
    begin
      # Solid Cacheのテーブル存在確認のみ（read/writeテストはskip）
      adapter = Rails.cache.class.name
    #{'  '}
      if adapter.include?('SolidCache')
        ActiveRecord::Base.establish_connection(:cache)
        if ActiveRecord::Base.connection.table_exists?('solid_cache_entries')
          puts 'cache_ok'
        else
          puts 'cache_failed|Table not found'
        end
        ActiveRecord::Base.establish_connection(:primary)
      else
        puts 'cache_ok|Different adapter'
      end
    #{'  '}
    rescue => e
      puts "cache_error|\#{e.message}"
    end
  RUBY

  result = run_rails_command(cache_check_code)

  if result.strip == 'cache_ok'
    true
  else
    error_line = result.lines.find { |l| l.include?('|') }
    if error_line
      _, error_msg = error_line.strip.split('|', 2)
      Rails.logger.warn "Solid Cache check failed: #{error_msg}" if defined?(Rails)
    end
    false
  end
rescue StandardError => e
  Rails.logger.warn "Solid Cache check error: #{e.message}" if defined?(Rails)
  false
end

def check_solid_cable_status
  # Solid Cableの動作確認

  cable_check_code = <<~RUBY
    begin
      # Solid Cableアダプタの確認
      adapter = ActionCable.server.config.cable&.[](:adapter) || 'unknown'
    #{'  '}
      if adapter.to_s == 'solid_cable'
        # テーブル存在確認
        ActiveRecord::Base.establish_connection(:cable)
        if ActiveRecord::Base.connection.table_exists?('solid_cable_messages')
          puts 'cable_ok'
        else
          puts 'cable_failed|Table not found'
        end
        ActiveRecord::Base.establish_connection(:primary)
      else
        puts 'cable_unused|Adapter not solid_cable'
      end
    rescue => e
      puts "cable_error|\#{e.message}"
    end
  RUBY

  result = run_rails_command(cable_check_code)

  if result.strip == 'cable_ok'
    true
  elsif result.include?('cable_unused')
    true # 未使用でも正常とみなす
  else
    error_line = result.lines.find { |l| l.include?('|') }
    if error_line
      _, error_msg = error_line.strip.split('|', 2)
      Rails.logger.warn "Solid Cable check failed: #{error_msg}" if defined?(Rails)
    end
    false
  end
rescue StandardError => e
  Rails.logger.warn "Solid Cable check error: #{e.message}" if defined?(Rails)
  false
end

def check_solid_queue_in_puma_status
  # Solid Queue（Puma内）の動作確認
  queue_check_code = <<~RUBY
    begin
      # Active Job adapter確認
      adapter = ActiveJob::Base.queue_adapter
      if adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
        # データベース接続確認
        ActiveRecord::Base.establish_connection(:queue)
        if ActiveRecord::Base.connection.table_exists?('solid_queue_jobs')
          # テストジョブエンキュー
          test_job_id = SecureRandom.hex(8)
          ActiveJob::Base.connection.exec_query(
            "INSERT INTO solid_queue_jobs (queue_name, class_name, arguments, active_job_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            "Test Job Insert",
            ['test', 'TestJob', '[]', test_job_id, Time.current, Time.current]
          )
          # テストジョブ削除
          ActiveJob::Base.connection.exec_query(
            "DELETE FROM solid_queue_jobs WHERE active_job_id = ?",
            "Test Job Delete",
            [test_job_id]
          )
          puts 'queue_ok'
        else
          puts 'queue_failed|Jobs table not found'
        end
        ActiveRecord::Base.establish_connection(:primary)
      else
        puts 'queue_unused|Adapter not SolidQueue'
      end
    rescue => e
      puts "queue_error|\#{e.message}"
    end
  RUBY

  result = run_rails_command(queue_check_code)

  if result.strip == 'queue_ok'
    true
  else
    error_line = result.lines.find { |l| l.include?('|') }
    if error_line
      _, error_msg = error_line.strip.split('|', 2)
      Rails.logger.warn "Solid Queue check failed: #{error_msg}" if defined?(Rails)
    end
    false
  end
rescue StandardError => e
  Rails.logger.warn "Solid Queue check error: #{e.message}" if defined?(Rails)
  false
end

def safe_gets(prompt = '')
  print prompt unless prompt.empty?
  input = gets
  return nil if input.nil?

  input.chomp.gsub(/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/, '')
end

def countdown_return(seconds, message = 'メニューに戻ります')
  print_info "#{message}... "
  seconds.downto(1) do |i|
    print "#{i} "
    $stdout.flush
    sleep 1
  end
  puts ''
end

def main_loop
  FileUtils.chdir APP_ROOT do
    loop do
      system('clear') || system('cls')
      show_logo
      show_menu

      choice = safe_gets('選択してください (a-l, x): ')

      # 入力が中断された場合の処理
      if choice.nil?
        puts ''
        print_info '入力が中断されました。終了します。'
        break
      end

      case choice
      when 'a'
        setup_new_installation
      when 'b'
        cleanup_and_start
      when 'c'
        check_domain_config
      when 'd'
        switch_domain
      when 'e'
        manage_accounts
      when 'f'
        manage_password
      when 'g'
        delete_account
      when 'h'
        create_oauth_token
      when 'i'
        generate_vapid_keys
      when 'j'
        migrate_to_r2
      when 'k'
        manage_remote_image_cache
      when 'l'
        import_mastodon_backup
      when 'm'
        process_follow_csv
      when 'x'
        puts ''
        print_success 'letter統合管理ツールを終了します'
        break
      else
        puts ''
        print_error '無効な選択です。a-l, xを入力してください。'
        puts ''
        countdown_return(2)
        next
      end

      next if choice == 'x'

      puts ''
      puts ''
      # Enterキーでメニューに戻る
      safe_gets('Enterキーを押してメニューに戻ります...')
    end
  end
end

# ==============================================
# Mastodonバックアップインポート機能
# ==============================================

def import_mastodon_backup
  puts ''
  print_header 'Mastodonのバックアップからインポート'

  # 1. ダンプファイルのパスを取得
  dump_path = get_mastodon_dump_path
  return unless dump_path

  # 2. ダンプファイルからローカルアカウント一覧を取得
  local_accounts = scan_local_accounts(dump_path)
  return unless local_accounts&.any?

  # 3. ローカルアカウントを選択
  selected_account = select_mastodon_account(local_accounts)
  return unless selected_account

  # 4. インポート先のローカルActorを選択
  actor = select_local_actor_for_import
  return unless actor

  # 5. メディアドメインを入力
  puts ''
  print_info '移行元のMastodonインスタンスがCloudflare R2を使っていた場合は、そのドメインを指定することでメディアも移行できる可能性があります'
  print_info '移行元メディアドメインを入力してください。空欄の場合はメディアの移行がスキップされます'
  puts ''
  media_domain = safe_gets('移行元メディアドメイン: ')
  return unless media_domain
  
  media_domain = media_domain.strip
  media_domain = nil if media_domain.empty?

  # 6. インポート実行
  result = perform_mastodon_import(dump_path, selected_account[:username], actor, media_domain)

  puts result[:success] ? "✅ インポート完了: #{result[:count]}件" : '❌ インポート失敗'
  puts ''
  safe_gets('Enterキーを押してメニューに戻ります...')
end

def get_mastodon_dump_path
  puts ''
  print_info 'Mastodonのデータベースダンプファイル（PostgreSQL形式）を指定してください'
  
  # Docker環境を検出してガイダンス表示
  if docker_environment?
    puts ''
    print_info '🐳 Docker環境を検出しました'
    puts '📁 ホストファイルにアクセスするには、以下の方法でコンテナを起動してください:'
    puts ''
    puts '   方法1: 特定ディレクトリをマウント'
    puts '   sudo docker-compose run --rm -v /path/to/files:/app/import web rails runner bin/letter_manager.rb'
    puts '   → /app/import/your_file.dump を指定'
    puts ''
    puts '   方法2: ホームディレクトリ全体をマウント'  
    puts '   sudo docker-compose run --rm -v $HOME:/host web rails runner bin/letter_manager.rb'
    puts '   → /host/path/to/your_file.dump を指定'
    puts ''
    puts '   方法3: ファイルをコンテナにコピー'
    puts '   sudo docker cp /path/to/file.dump $(sudo docker-compose ps -q web):/app/'
    puts '   → /app/file.dump を指定'
    puts ''
  end
  
  puts ''

  dump_path = safe_gets('ダンプファイルのパス: ')
  return nil if dump_path.nil? || dump_path.strip.empty?

  dump_path = dump_path.strip

  unless File.exist?(dump_path)
    print_error "ファイルが見つかりません: #{dump_path}"
    if docker_environment?
      puts ''
      print_warning '💡 Docker環境では、上記の方法でホストファイルをマウントしてください'
    end
    return nil
  end

  # ファイルタイプを確認
  file_type = `file "#{dump_path}" 2>/dev/null`.strip
  if $?.success? && !file_type.empty?
    # gzipファイル、PostgreSQLファイル、または一般的な拡張子の場合は警告をスキップ
    is_likely_valid = file_type.include?('PostgreSQL') || 
                     file_type.include?('gzip') || 
                     file_type.include?('data') ||
                     dump_path.end_with?('.dump', '.sql', '.gz')
    
    unless is_likely_valid
      print_warning 'PostgreSQLダンプファイルではない可能性があります'
      puts "ファイルタイプ: #{file_type}"

      return nil unless safe_gets('続行しますか？ (y/N): ').downcase == 'y'
    end
  else
    print_warning 'ファイルタイプを確認できませんでした'
    unless dump_path.end_with?('.dump', '.sql', '.gz')
      print_warning 'ファイル拡張子もPostgreSQLダンプファイルのものではありません'
      return nil unless safe_gets('続行しますか？ (y/N): ').downcase == 'y'
    end
  end

  print_success "ダンプファイルを確認しました: #{dump_path}"
  dump_path
end

def scan_local_accounts(dump_path)
  print 'ローカルアカウントを検索中...'

  # gzip圧縮ファイルかチェック
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_uncompressed_scan_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return nil unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # accountsテーブルを抽出
  accounts_file = "/tmp/mastodon_accounts_scan_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=accounts', '--no-owner',
         '--no-privileges', "--file=#{accounts_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    return nil
  end

  # ローカルアカウントを抽出
  local_accounts = []
  in_copy_data = false

  File.readlines(accounts_file).each do |line|
    if line.include?('COPY public.accounts')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'

    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 3

    username = fields[0]
    domain = fields[1]

    # ローカルアカウント（domain が NULL）のみ、かつユーザ名が有効
    if (domain == '\\N' || domain.nil? || domain.empty?) &&
       !username.nil? && !username.empty? && !username.include?('@') && !username.include?('.')
      local_accounts << { username: username, id: fields[27] }
    end
  end

  FileUtils.rm_f(accounts_file)

  puts " ✅ #{local_accounts.length}件"
  local_accounts
end

def select_mastodon_account(local_accounts)
  puts ''
  puts 'インポート元のMastodonローカルアカウントを選択してください:'

  local_accounts.each_with_index do |account, index|
    puts "  #{index + 1}. @#{account[:username]}"
  end

  choice = safe_gets("選択 (1-#{local_accounts.length}): ").to_i

  if choice.between?(1, local_accounts.length)
    selected = local_accounts[choice - 1]
    print_success "選択: @#{selected[:username]}"
    selected
  else
    print_error '無効な選択です'
    nil
  end
end

def select_local_actor_for_import
  puts ''
  print_info 'インポート先のローカルアカウントを選択してください'

  # ローカルアカウントを取得
  code = <<~RUBY
    actors = Actor.where(domain: nil).order(:username)
    if actors.empty?
      puts "LOCAL_ACTORS_EMPTY"
    else
      actors.each do |actor|
        puts "ACTOR|\#{actor.id}|\#{actor.username}|\#{actor.display_name}|\#{actor.posts_count}"
      end
    end
  RUBY

  result = run_rails_command(code)

  if result.include?('LOCAL_ACTORS_EMPTY')
    print_error 'ローカルアカウントが見つかりません'
    return nil
  end

  # 結果を解析
  actors = []
  result.lines.each do |line|
    next unless line.start_with?('ACTOR|')

    parts = line.chomp.split('|')
    next unless parts.length >= 5

    actors << {
      id: parts[1].to_i,
      username: parts[2],
      display_name: parts[3],
      posts_count: parts[4].to_i
    }
  end

  if actors.empty?
    print_error '利用可能なローカルアカウントが見つかりません'
    return nil
  end

  puts ''
  actors.each_with_index do |actor, index|
    display_name = actor[:display_name].empty? ? actor[:username] : actor[:display_name]
    puts "  #{index + 1}) @#{actor[:username]} - #{display_name} (投稿数: #{actor[:posts_count]})"
  end

  choice = safe_gets("選択してください (1-#{actors.length}): ").to_i

  if choice.between?(1, actors.length)
    selected_actor = actors[choice - 1]

    # Actorオブジェクトを取得
    actor_code = "Actor.find(#{selected_actor[:id]})"
    run_rails_command(actor_code)

    print_success "選択されたアカウント: @#{selected_actor[:username]}"

    SimpleActor.new(selected_actor[:id], selected_actor[:username])
  else
    print_error '無効な選択です'
    nil
  end
end

def extract_mastodon_statuses_with_account_id(dump_path, account_id)
  print '投稿データを抽出中...'

  # gzip展開
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_uncompressed_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return nil unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # statuses抽出
  statuses_file = "/tmp/mastodon_statuses_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=statuses', '--no-owner',
         '--no-privileges', "--file=#{statuses_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    FileUtils.rm_f(statuses_file)
    return nil
  end

  # SQLファイルを解析
  statuses = parse_mastodon_statuses_sql_with_account_id(statuses_file, account_id)

  FileUtils.rm_f(statuses_file)

  puts " ✅ #{statuses.length}件"
  statuses
end

def extract_mastodon_statuses(dump_path, mastodon_username)
  print '投稿データを抽出中...'

  # gzip展開
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_uncompressed_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return nil unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # accounts抽出
  accounts_file = "/tmp/mastodon_accounts_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=accounts', '--no-owner',
         '--no-privileges', "--file=#{accounts_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    FileUtils.rm_f(accounts_file)
    File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)
    return nil
  end

  # アカウントID取得
  account_id = find_mastodon_account_id(accounts_file, mastodon_username)
  FileUtils.rm_f(accounts_file)

  unless account_id
    puts ' ❌'
    File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)
    return nil
  end

  # statuses抽出
  statuses_file = "/tmp/mastodon_statuses_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=statuses', '--no-owner',
         '--no-privileges', "--file=#{statuses_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    FileUtils.rm_f(statuses_file)
    return nil
  end

  # 投稿解析
  statuses = parse_mastodon_statuses_sql(statuses_file, account_id)
  FileUtils.rm_f(statuses_file)

  puts " ✅ #{statuses&.length || 0}件"
  statuses
end

def find_mastodon_account_id(accounts_file, username)
  in_copy_data = false
  local_accounts_found = []

  File.readlines(accounts_file).each do |line|
    if line.include?('COPY public.accounts')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'

    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 28 # 必要なフィールド数を厳格化

    account_username = fields[0]
    account_domain = fields[1]
    account_id = fields[27]

    # ローカルアカウントのみを対象（domainがNULL）
    next unless account_domain == '\\N' || account_domain.nil? || account_domain.empty?

    # ユーザ名の有効性チェック
    next if account_username.nil? || account_username.empty? || account_username == '\\N'

    # ドメイン名やメールアドレス形式を除外
    next if account_username.include?('.') || account_username.include?('@')

    # システムアカウント名を除外
    next if account_username.start_with?('mystech')

    local_accounts_found << {
      username: account_username,
      id: account_id
    }

    # 指定されたユーザ名と完全一致
    return account_id if account_username == username
  end

  puts "❌ 指定されたユーザ名 '#{username}' のローカルアカウントが見つかりませんでした"
  nil
end

def find_mastodon_account_id_for_media(dump_path, username)
  # gzip展開
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_account_id_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return nil unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # accounts抽出
  accounts_file = "/tmp/mastodon_accounts_id_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=accounts', '--no-owner',
         '--no-privileges', "--file=#{accounts_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)

  unless $CHILD_STATUS.success?
    FileUtils.rm_f(accounts_file)
    return nil
  end

  account_id = find_mastodon_account_id(accounts_file, username)
  FileUtils.rm_f(accounts_file)

  account_id
end

def perform_mastodon_import(dump_path, mastodon_username, actor, media_domain)
  print 'インポート処理を開始...'

  # アカウントIDを取得
  account_id = find_mastodon_account_id_for_media(dump_path, mastodon_username)
  unless account_id
    puts ' ❌ アカウントIDが見つかりません'
    return { success: false, count: 0 }
  end

  puts "使用するアカウントID: #{account_id}"

  # 1. 投稿を抽出
  puts '1. 投稿を抽出中...'
  all_statuses = extract_mastodon_statuses_with_account_id(dump_path, account_id)

  if all_statuses.nil? || all_statuses.empty?
    puts ' ❌ 投稿が見つかりませんでした'
    return { success: false, count: 0 }
  end

  # 2. 画像付き投稿の情報を取得
  puts '2. 画像情報を取得中...'
  image_post_ids = extract_image_post_ids(dump_path, account_id)
  image_posts_map = {}
  image_post_ids.each do |img_post|
    image_posts_map[img_post[:status_id]] = img_post
  end

  # 3. 投稿をインポート
  puts "3. 投稿をインポート中... (#{all_statuses.length}件)"
  imported_count = 0
  batch_size = 100
  total_batches = (all_statuses.length / batch_size.to_f).ceil
  
  all_statuses.each_slice(batch_size).with_index do |batch, batch_index|
    progress = ((batch_index + 1).to_f / total_batches * 100).round(1)
    puts "\nバッチ #{batch_index + 1}/#{total_batches} (#{progress}%) - #{imported_count}件完了"
    
    # バッチ用の画像情報を準備
    batch_image_infos = batch.map { |status| image_posts_map[status[:id]] }
    
    batch_import_code = <<~RUBY
      require 'letter/snowflake'
      actor = Actor.find(#{actor.id})
      batch_statuses = #{batch.inspect}
      batch_image_infos = #{batch_image_infos.inspect}
      media_domain = #{media_domain.inspect}
      
      imported_count = 0
      
      batch_statuses.each_with_index do |status_info, batch_index|
        begin
          created_at = Time.parse(status_info[:created_at] + ' UTC')
          post_id = Letter::Snowflake.generate_at(created_at)
          
          # リブログの場合はスキップ
          if status_info[:reblog_of_id]
            imported_count += 1
            next
          end
          
          # 既存投稿をチェック
          existing_obj = ActivityPubObject.find_by(id: post_id)
          should_process_image = false
          
          if existing_obj
            # 既存投稿に画像がアタッチされているかチェック
            if existing_obj.media_attachments.any?
              # 既に画像がある場合はスキップ
              next
            else
              obj = existing_obj
              should_process_image = true
            end
          else
            # 新規投稿作成
            content = status_info[:content]
            content = '' if content.nil? || content == '\\N'
            
            obj = ActivityPubObject.new(
              id: post_id,
              ap_id: "https://\#{ENV['DOMAIN'] || 'localhost'}/objects/\#{post_id}",
              actor: actor,
              object_type: 'Note',
              content: content,
              published_at: created_at,
              visibility: 'public',
              local: true,
              created_at: created_at,
              updated_at: Time.current
            )
            obj.save!(validate: false)
            should_process_image = true
          end
          
          # 画像処理（メディアドメインが指定されている場合のみ）
          image_info = batch_image_infos[batch_index]
          if media_domain && image_info && image_info[:file_name] && should_process_image
            # media_attachment_idを使ってURL構築
            if image_info[:media_id]
              media_id_str = image_info[:media_id].to_s.rjust(18, '0')
              path_parts = []
              6.times { |i| path_parts << media_id_str[i * 3, 3] }
              r2_url = "https://\#{media_domain}/media_attachments/files/\#{path_parts.join('/')}/original/\#{image_info[:file_name]}"
            else
              # フォールバック: status_idを使用
              status_id_str = post_id.to_s.rjust(18, '0')
              path_parts = []
              6.times { |i| path_parts << status_id_str[i * 3, 3] }
              r2_url = "https://\#{media_domain}/media_attachments/files/\#{path_parts.join('/')}/original/\#{image_info[:file_name]}"
            end
            
            begin
              require 'net/http'
              require 'openssl'
              require 'tempfile'
              
              uri = URI.parse(r2_url)
              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              http.read_timeout = 30
              
              request = Net::HTTP::Get.new(uri.request_uri)
              response = http.request(request)
              
              if response.code == '200'
                content_type = response.content_type || 'image/jpeg'
                ext = case content_type
                      when /jpeg|jpg/i then '.jpg'
                      when /png/i then '.png'
                      when /gif/i then '.gif'
                      else '.jpg'
                      end
                
                temp_file = Tempfile.new(['media', ext])
                temp_file.binmode
                temp_file.write(response.body)
                temp_file.rewind
                
                media_type = content_type.start_with?('video') ? 'video' : 'image'
                
                media_attachment = MediaAttachment.create!(
                  actor: actor,
                  object: obj,
                  media_type: media_type,
                  content_type: content_type,
                  file_name: image_info[:file_name],
                  file_size: response.body.size,
                  remote_url: r2_url,
                  description: image_info[:description] || ''
                )
                
                media_attachment.attach_file_with_folder(
                  io: temp_file,
                  filename: media_attachment.file_name,
                  content_type: media_attachment.content_type
                )
                
                temp_file.close
                temp_file.unlink
              end
            rescue => e
              # 画像処理エラーは無視して続行
            end
          end
          
          imported_count += 1
          
        rescue => e
          # 個別の投稿エラーは無視して続行
        end
      end
      
      puts "BATCH_IMPORTED:\#{imported_count}"
    RUBY
    
    result = run_rails_command(batch_import_code)
    if result.match(/BATCH_IMPORTED:(\d+)/)
      batch_imported = $1.to_i
      imported_count += batch_imported
      print "#{batch_imported}件"
    else
      print "×"
    end
  end

  puts "\n✅ インポート完了: #{imported_count}/#{all_statuses.length}件"
  { success: true, count: imported_count }
end

def parse_mastodon_statuses_sql_with_account_id(sql_file, target_account_id)
  statuses = []
  in_copy_data = false
  matched_count = 0

  File.readlines(sql_file).each do |line|
    if line.include?('COPY public.statuses')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'

    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")

    next if fields.length < 20

    status_id = fields[0]
    account_id = fields[15]
    content = fields[2]
    created_at = fields[3]
    in_reply_to_id = fields[5]
    reblog_of_id = fields[6]

    next unless account_id == target_account_id

    matched_count += 1

    statuses << {
      id: status_id,
      content: content && content != '\\N' ? content.gsub('\\n', "\n").gsub('\\t', "\t") : '',
      created_at: created_at,
      in_reply_to_id: in_reply_to_id && in_reply_to_id != '\\N' ? in_reply_to_id : nil,
      reblog_of_id: reblog_of_id && reblog_of_id != '\\N' ? reblog_of_id : nil
    }
  end

  statuses
end

def parse_mastodon_statuses_sql(sql_file, target_account_id)
  statuses = []
  in_copy_data = false

  File.readlines(sql_file).each do |line|
    if line.include?('COPY public.statuses')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'

    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 20

    status_id = fields[0]
    account_id = fields[15]
    content = fields[2]
    created_at = fields[3]
    in_reply_to_id = fields[5]
    reblog_of_id = fields[6]

    next unless account_id == target_account_id

    statuses << {
      id: status_id,
      content: content && content != '\\N' ? content.gsub('\\n', "\n").gsub('\\t', "\t") : '',
      created_at: created_at,
      in_reply_to_id: in_reply_to_id && in_reply_to_id != '\\N' ? in_reply_to_id : nil,
      reblog_of_id: reblog_of_id && reblog_of_id != '\\N' ? reblog_of_id : nil
    }
  end

  statuses
end

# メディアのダウンロード・アップロード処理
def try_upload_media(r2_url, media_info, actor)
  require 'net/http'
  require 'openssl'
  require 'tempfile'

  begin
    uri = URI.parse(r2_url)

    # HTTPSでダウンロード
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request['User-Agent'] = 'letter/0.1 (Mastodon Import)'

    response = http.request(request)

    # リダイレクト対応
    if response.code.to_i >= 300 && response.code.to_i < 400 && response['location']
      redirect_uri = URI.parse(response['location'])
      http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      http.use_ssl = (redirect_uri.scheme == 'https')
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Get.new(redirect_uri.request_uri)
      request['User-Agent'] = 'letter/0.1 (Mastodon Import)'
      response = http.request(request)
    end

    if response.code == '200'
      # content-typeから拡張子を推定
      content_type = response.content_type || media_info[:content_type] || 'image/jpeg'

      ext = case content_type
            when /jpeg|jpg/i then '.jpg'
            when /png/i then '.png'
            when /gif/i then '.gif'
            when /webp/i then '.webp'
            when /avif/i then '.avif'
            when /video/i then '.mp4'
            when /audio/i then '.mp3'
            else '.jpg'
            end

      # URLから拡張子を取得する試み
      ext = ".#{Regexp.last_match(1).downcase}" if r2_url =~ /\.(jpg|jpeg|png|gif|webp|avif|mp4|mp3)$/i

      # 一時ファイルの作成
      temp_file = Tempfile.new(['media', ext])
      temp_file.binmode
      temp_file.write(response.body)
      temp_file.rewind

      file_name = if media_info[:shortcode] && media_info[:shortcode] != '\\N'
                    "#{media_info[:shortcode]}#{ext}"
                  else
                    "media_#{SecureRandom.hex(8)}#{ext}"
                  end

      # メディアタイプを判定
      media_type = case content_type
                   when /video/i then 'video'
                   when /audio/i then 'audio'
                   else 'image'
                   end

      # メディアAttachmentデータを返す（実際の作成は後で）
      media_attachment_data = {
        media_type: media_type,
        content_type: content_type,
        file_name: file_name,
        file_size: response.body.size,
        description: media_info[:description] || '',
        temp_file: temp_file
      }

      { success: true, media_attachment: media_attachment_data }
    else
      { success: false, error: "HTTP #{response.code}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end
end

def extract_image_post_ids(dump_path, account_id)
  # gzip展開
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_media_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return [] unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # media_attachments抽出
  media_file = "/tmp/mastodon_media_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=media_attachments', '--no-owner',
         '--no-privileges', "--file=#{media_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  # statuses抽出
  statuses_file = "/tmp/mastodon_statuses_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=statuses', '--no-owner',
         '--no-privileges', "--file=#{statuses_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  # メディアアタッチメント情報を収集（media_attachment_id => file_info）
  media_attachments = {}
  in_copy_data = false

  File.readlines(media_file).each do |line|
    if line.include?('COPY public.media_attachments')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'
    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 13

    media_account_id = fields[11]
    next unless media_account_id == account_id

    file_name = fields[1]
    next unless file_name && file_name != '\\N' && !file_name.empty?

    media_attachment_id = fields[0] # media_attachmentのID
    description = fields[13] && fields[13] != '\N' ? fields[13] : ''
    created_at = fields[6]

    media_attachments[media_attachment_id] = {
      file_name: file_name,
      description: description,
      created_at: created_at
    }
  end

  # media_attachmentsのstatus_idを使って直接画像付き投稿を特定
  image_posts = []
  status_ids_with_media = {}

  # media_attachmentsからstatus_idと画像情報を収集
  media_attachments.each do |media_id, media_info|
    # media_attachmentsテーブルからstatus_idを取得する必要がある
    # これは既に収集済みのmedia_attachmentsに含まれていないので、再度抽出が必要
  end

  # media_attachmentsを再読み込みしてフィールド構造を確認
  media_file_reload = "/tmp/mastodon_media_reload_#{Time.now.to_i}.sql"
  
  restore_result = system('pg_restore', '--data-only', '--table=media_attachments', '--no-owner',
         '--no-privileges', "--file=#{media_file_reload}", actual_dump_path)

  # pg_restoreが失敗した場合はファイルが存在しない
  if !restore_result || !File.exist?(media_file_reload)
    puts ' ❌'
    puts "メディア情報の抽出に失敗しました"
    File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)
    return []
  end

  in_copy_data = false

  File.readlines(media_file_reload).each do |line|
    if line.include?('COPY public.media_attachments')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'
    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 13

    media_account_id = fields[11]
    next unless media_account_id == account_id

    file_name = fields[1]
    next unless file_name && file_name != '\\N' && !file_name.empty?

    attachment_status_id = fields[0]  # COPY文によると[0]がstatus_id
    media_attachment_id = fields[12]  # COPY文によると[12]がmedia_attachmentのid
    description = fields[13] && fields[13] != '\N' ? fields[13] : ''
    created_at = fields[6]

    # status_idが有効な場合のみ
    next unless attachment_status_id && attachment_status_id != '\\N' && !attachment_status_id.empty?

    status_ids_with_media[attachment_status_id] = {
      file_name: file_name,
      description: description,
      created_at: created_at,
      media_id: media_attachment_id
    }
  end

  File.delete(media_file_reload)

  # statusesテーブルから対応する投稿内容を取得
  in_copy_data = false
  posts_checked = 0
  account_posts_found = 0

  File.readlines(statuses_file).each do |line|
    if line.include?('COPY public.statuses')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'
    next unless in_copy_data && line.include?("\t")

    fields = line.chomp.split("\t")
    next if fields.length < 23

    status_id = fields[0]
    content = fields[2]
    status_account_id = fields[15]

    posts_checked += 1

    # 指定されたアカウントの投稿のみ
    next unless status_account_id == account_id

    account_posts_found += 1

    # 画像付き投稿のみ
    next unless status_ids_with_media[status_id]

    media_info = status_ids_with_media[status_id]
    processed_content = content && content != '\\N' ? content.gsub('\\n', "\n").gsub('\\t', "\t") : ''

    image_posts << {
      status_id: status_id,
      file_name: media_info[:file_name],
      description: media_info[:description],
      created_at: media_info[:created_at],
      content: processed_content,
      media_id: media_info[:media_id]
    }

    if image_posts.length <= 5
    end
  end

  FileUtils.rm_f(media_file)
  FileUtils.rm_f(statuses_file)

  image_posts
end

def extract_mastodon_media_attachments(dump_path, target_account_id)
  print 'メディアデータを抽出中...'

  # gzip展開
  actual_dump_path = dump_path
  temp_uncompressed = nil

  if dump_path.end_with?('.gz')
    temp_uncompressed = "/tmp/mastodon_media_uncompressed_#{Time.now.to_i}.dump"
    system('zcat', dump_path, out: temp_uncompressed, err: File::NULL)
    return nil unless $CHILD_STATUS.success?

    actual_dump_path = temp_uncompressed
  end

  # media_attachments抽出
  media_file = "/tmp/mastodon_media_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=media_attachments', '--no-owner',
         '--no-privileges', "--file=#{media_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    FileUtils.rm_f(media_file)
    return {}
  end

  # statusesも抽出
  statuses_file = "/tmp/mastodon_statuses_media_#{Time.now.to_i}.sql"
  system('pg_restore', '--data-only', '--table=statuses', '--no-owner',
         '--no-privileges', "--file=#{statuses_file}", actual_dump_path,
         out: File::NULL, err: File::NULL)

  unless $CHILD_STATUS.success?
    puts ' ❌'
    FileUtils.rm_f(media_file)
    FileUtils.rm_f(statuses_file)
    return {}
  end

  # status_idとmedia_attachmentの関連を解析
  media_attachments = parse_mastodon_media_sql(media_file, statuses_file, target_account_id)

  FileUtils.rm_f(media_file)
  FileUtils.rm_f(statuses_file)

  media_attachments
end

def parse_mastodon_media_sql(media_file, statuses_file, target_account_id)
  # media_attachmentsから該当するメディアを直接抽出（account_idで絞り込み）
  media_attachments = {}
  in_copy_data = false
  line_count = 0
  media_count = 0

  File.readlines(media_file).each do |line|
    if line.include?('COPY public.media_attachments')
      in_copy_data = true
      next
    end

    break if in_copy_data && line.strip == '\\.'
    next unless in_copy_data && line.include?("\t")

    line_count += 1
    fields = line.chomp.split("\t")

    next if fields.length < 10

    # account_idで直接フィルタリング（フィールド[11]）
    media_account_id = fields[11]
    next unless media_account_id == target_account_id

    status_id = fields[12]

    # remote_urlを取得（フィールド[5]）
    remote_url = fields[5]

    # ローカルファイルの場合はfile_file_nameを使用
    if remote_url.nil? || remote_url.empty? || remote_url == '\\N'
      file_name = fields[1]
      next unless file_name && file_name != '\\N' && !file_name.empty?

      remote_url = "local_file:#{file_name}"

      # ファイル情報がない場合はスキップ

    end

    media_count += 1

    media_info = {
      id: fields[0],
      remote_url: remote_url,
      content_type: fields[2],
      file_size: fields[3],
      metadata: fields[10] && fields[10] != '\\N' ? fields[10] : nil,
      description: fields[13],
      blurhash: fields[15] && fields[15] != '\\N' ? fields[15] : nil,
      created_at: fields[6]
    }

    media_attachments[status_id] ||= []
    media_attachments[status_id] << media_info
  end

  # 一時ファイルをクリーンアップ
  File.delete(temp_uncompressed) if temp_uncompressed && File.exist?(temp_uncompressed)
  [media_file, media_file_reload, statuses_file].each do |file|
    File.delete(file) if file && File.exist?(file)
  end

  media_attachments
end

def download_and_upload_media(media_url, filename, content_type)
  return nil if media_url.nil? || media_url.empty? || media_url == '\\N'

  begin
    # メディアをダウンロード
    uri = URI.parse(media_url)
    response = Net::HTTP.get_response(uri)
    return nil unless response.code == '200'

    # 一時ファイルに保存
    temp_file = Tempfile.new(['media', File.extname(filename)])
    temp_file.binmode
    temp_file.write(response.body)
    temp_file.rewind

    # MediaAttachmentCreationServiceを使用してアップロード
    media_service = MediaAttachmentCreationService.new(user: nil)
    media_attachment = media_service.create_from_file(temp_file)

    temp_file.close
    temp_file.unlink

    media_attachment&.file&.url
  rescue StandardError => e
    nil
  end
end

def process_follow_csv
  print_header 'CSVファイルからフォロー処理'
  
  csv_path_input = safe_gets('CSVファイルパス: ')
  
  if csv_path_input.nil? || csv_path_input.strip.empty?
    print_info 'フォロー処理をキャンセルしました'
    return
  end
  
  csv_path = File.expand_path(csv_path_input.strip)
  
  unless File.exist?(csv_path)
    print_error "CSVファイルが見つかりません: #{csv_path}"
    return
  end
  
  print_info "CSVファイルを読み込み中: #{csv_path}"
  
  # ローカルユーザを選択
  actor = select_local_actor_for_import
  return unless actor
  
  # CSVファイルを解析してフォロー処理
  process_follow_list(csv_path, actor)
end

def process_follow_list(csv_path, actor)
  require 'csv'
  
  accounts_to_follow = []
  
  # CSVファイルを読み込み
  CSV.foreach(csv_path, headers: true) do |row|
    account_address = row['Account address']&.strip
    next if account_address.nil? || account_address.empty?
    next if account_address == actor.username + '@' + ENV.fetch('ACTIVITYPUB_DOMAIN', 'localhost')
    
    accounts_to_follow << account_address
  end
  
  print_info "CSVから #{accounts_to_follow.length}件のアカウントを読み込みました"
  
  if accounts_to_follow.empty?
    print_warning 'フォロー対象のアカウントが見つかりません'
    return
  end
  
  # 既存のフォロー関係をチェック
  print_info '既存のフォロー関係をチェック中...'
  
  check_code = <<~RUBY
    actor = Actor.find(#{actor.id})
    accounts_to_check = #{accounts_to_follow.inspect}
    results = {}
    
    accounts_to_check.each do |account_address|
      # アカウント形式を解析
      if account_address.include?('@')
        username, domain = account_address.split('@')
        target_actor = Actor.find_by(username: username, domain: domain)
        
        if target_actor
          already_following = Follow.exists?(actor: actor, target_actor: target_actor)
          results[account_address] = already_following ? 'following' : 'not_following'
        else
          results[account_address] = 'not_found'
        end
      else
        results[account_address] = 'invalid_format'
      end
    end
    
    results.each { |addr, status| puts "\#{addr}|\#{status}" }
  RUBY
  
  result = run_rails_command(check_code)
  follow_status = {}
  
  result.strip.lines.each do |line|
    next if line.strip.start_with?('ActivityPub configured') || line.strip.empty?
    
    parts = line.strip.split('|')
    next unless parts.length == 2
    
    follow_status[parts[0]] = parts[1]
  end
  
  # フィルタリング: まだフォローしていないアカウントのみ
  new_follows = accounts_to_follow.select { |addr| follow_status[addr] == 'not_following' || follow_status[addr] == 'not_found' }
  already_following = accounts_to_follow.select { |addr| follow_status[addr] == 'following' }
  
  puts ''
  print_info "既にフォロー済み: #{already_following.length}件"
  print_info "新規フォロー対象: #{new_follows.length}件"
  
  if already_following.any?
    puts ''
    puts '既にフォロー済みのアカウント:'
    already_following.each { |addr| puts "  • #{addr}" }
  end
  
  if new_follows.empty?
    print_success '全てのアカウントを既にフォロー済みです'
    return
  end
  
  puts ''
  puts '新規フォロー対象のアカウント:'
  new_follows.each_with_index do |account, index|
    puts "  #{index + 1}. #{account}"
  end
  puts ''
  
  answer = safe_gets("#{new_follows.length}件の新しいアカウントをフォローしますか? (y/N): ")
  return unless answer&.downcase == 'y'
  
  print_info 'フォロー処理を開始します...'
  
  success_count = 0
  error_count = 0
  
  new_follows.each_with_index do |account_address, index|
    print "  (#{index + 1}/#{new_follows.length}) #{account_address}をフォロー中..."
    
    follow_code = <<~RUBY
      begin
        actor = Actor.find(#{actor.id})
        follow_result = actor.follow!('#{account_address.gsub("'", "\\'")}')
        puts follow_result ? 'SUCCESS' : 'ERROR:Follow failed'
      rescue => e
        puts "EXCEPTION:\\\#{e.message}"
      end
    RUBY
    
    result = run_rails_command(follow_code)
    filtered_result = result.strip.lines.reject do |line|
      line.strip.start_with?('ActivityPub configured') || line.strip.empty?
    end.first&.strip
    
    case filtered_result
    when 'SUCCESS'
      puts ' ✓'
      success_count += 1
    when /^ERROR:(.*)/
      puts " ✗ (#{$1})"
      error_count += 1
    when /^EXCEPTION:(.*)/
      puts " ✗ (例外: #{$1})"
      error_count += 1
    else
      puts ' ✗ (不明なエラー)'
      error_count += 1
    end
    
    # フォロー間隔を空ける
    sleep(0.5) if index < new_follows.length - 1
  end
  
  puts ''
  print_success "フォロー処理完了: 成功 #{success_count}件, 失敗 #{error_count}件"
  if already_following.any?
    print_info "既にフォロー済み: #{already_following.length}件をスキップしました"
  end
end

# スクリプト実行
main_loop if __FILE__ == $PROGRAM_NAME
