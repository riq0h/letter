#!/usr/bin/env ruby
require "fileutils"
require "openssl"
require "base64"
require "json"

APP_ROOT = File.expand_path("..", __dir__)

def system!(*args)
  system(*args, exception: true)
end

def print_header(message)
  puts "========================================"
  puts "#{message}"
  puts "========================================"
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

def show_logo
  puts " ██╗      ███████╗ ████████╗ ████████╗ ███████╗ ██████╗"
  puts " ██║      ██╔════╝ ╚══██╔══╝ ╚══██╔══╝ ██╔════╝ ██╔══██╗"
  puts " ██║      █████╗      ██║       ██║    █████╗   ██████╔╝"
  puts " ██║      ██╔══╝      ██║       ██║    ██╔══╝   ██╔══██╗"
  puts " ███████╗ ███████╗    ██║       ██║    ███████╗ ██║  ██║"
  puts " ╚══════╝ ╚══════╝    ╚═╝       ╚═╝    ╚══════╝ ╚═╝  ╚═╝"
  puts ""
end

def show_menu
  print_header "letter 統合管理メニュー"
  puts ""
  puts "サーバ管理:"
  puts "  1) 完全セットアップ (新規インストール)"
  puts "  2) サーバ起動・再起動 (クリーンアップ付き)"
  puts "  3) ドメイン設定確認"
  puts "  4) ドメイン切り替え"
  puts ""
  puts "アカウント管理:"
  puts "  5) アカウント作成・管理"
  puts "  6) アカウント削除"
  puts "  7) OAuthトークン生成"
  puts ""
  puts "システム管理:"
  puts "  8) VAPIDキー生成"
  puts "  9) Cloudflare R2 移行"
  puts ""
  puts "  0) 終了"
  puts ""
end

# 環境変数読み込み
def load_env_vars
  return {} unless File.exist?(".env")
  
  env_vars = {}
  File.readlines(".env").each do |line|
    line = line.strip
    next if line.empty? || line.start_with?("#")
    key, value = line.split("=", 2)
    env_vars[key] = value if key && value
  end
  env_vars
end

# Rails runner実行ヘルパー
def run_rails_command(code)
  env_vars = load_env_vars
  env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(" ")
  
  temp_file = "/tmp/rails_temp_#{Random.rand(10000)}.rb"
  File.write(temp_file, code)
  
  result = `#{env_string} bin/rails runner "#{temp_file}" 2>/dev/null`
  File.delete(temp_file) if File.exist?(temp_file)
  
  result
ensure
  File.delete(temp_file) if File.exist?(temp_file)
end

# 1. 完全セットアップ
def setup_new_installation
  puts ""
  print_header "letter セットアップスクリプト"
  print_info "実行時刻: #{Time.now}"
  puts ""

  # 環境ファイルの設定
  print_info "1. 環境ファイルの確認..."
  env_template = <<~ENV
    # ========================================
    # 重要設定
    # ========================================

    # ActivityPub上で使用するドメインを設定します。一度使ったものは再利用できません
    ACTIVITYPUB_DOMAIN=your-domain.example.com

    # WebPushを有効化するために必要なVAPID
    VAPID_PUBLIC_KEY=your_vapid_public_key
    VAPID_PRIVATE_KEY=your_vapid_private_key

    # ActivityPubではHTTPSでなければ通信できません（ローカル開発時は空欄可）
    ACTIVITYPUB_PROTOCOL=

    # ========================================
    # オブジェクトストレージ設定
    # ========================================

    S3_ENABLED=false
    # S3_ENDPOINT=
    # S3_BUCKET=
    # R2_ACCESS_KEY_ID=
    # R2_SECRET_ACCESS_KEY=
    # S3_ALIAS_HOST=
  ENV

  if File.exist?(".env")
    print_success ".envファイルが存在します"
    
    env_content = File.read(".env")
    missing_keys = []
    
    %w[ACTIVITYPUB_DOMAIN VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY].each do |key|
      unless env_content.match?(/^#{key}=.+/)
        missing_keys << key
      end
    end
    
    if missing_keys.any?
      print_warning "以下の必須設定が不足しています: #{missing_keys.join(', ')}"
      print_info "サンプル設定を .env.template として作成します"
      File.write(".env.template", env_template)
    else
      print_success "必須の環境変数が設定されています"
    end
  else
    print_warning ".envファイルが見つかりません。テンプレートを作成します"
    File.write(".env", env_template)
    print_info ".envファイルを作成しました。設定を編集してください:"
    print_info "  - ACTIVITYPUB_DOMAIN: あなたのドメイン"
    print_info "  - VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY: WebPush用キー"
    puts ""
    print_error "設定完了後、再度このスクリプトを実行してください"
    return
  end

  # 依存関係のインストール
  print_info "2. 依存関係のインストール..."
  system("bundle check") || system!("bundle install")
  print_success "依存関係をインストールしました"

  # データベースの確認と準備
  print_info "3. データベースの確認と準備..."
  
  if File.exist?("db/development.sqlite3")
    print_success "データベースファイルが存在します"
  else
    print_warning "データベースファイルが見つかりません。作成します..."
    begin
      system! "bin/rails db:create"
      print_success "データベースを作成しました"
    rescue => e
      print_error "データベース作成に失敗しました: #{e.message}"
      return
    end
  end

  # マイグレーションの実行
  print_info "マイグレーションの確認..."
  
  migrate_output = `bin/rails db:migrate:status 2>&1`
  if $?.success?
    pending_migrations = migrate_output.lines.select { |line| line.include?("down") }
    
    if pending_migrations.empty?
      print_success "すべてのマイグレーションが完了しています"
    else
      print_info "#{pending_migrations.count}個の未実行マイグレーションがあります"
      
      if system("bin/rails db:migrate 2>/dev/null")
        print_success "マイグレーションを実行しました"
      else
        print_warning "マイグレーションでエラーが発生しましたが、続行します"
      end
    end
  else
    print_warning "マイグレーション状態の確認に失敗しました。スキップします"
  end

  # ログとテンポラリファイルのクリーンアップ
  print_info "4. ログとテンポラリファイルのクリーンアップ..."
  system! "bin/rails log:clear tmp:clear"
  print_success "クリーンアップが完了しました"

  # 既存プロセスの確認と停止
  print_info "5. 既存プロセスの確認..."
  rails_running = system("pgrep -f 'rails server' > /dev/null 2>&1")
  queue_running = system("pgrep -f 'solid.*queue' > /dev/null 2>&1")

  if rails_running || queue_running
    print_warning "既存のプロセスが動作中です。停止します..."
    system("pkill -f 'solid.*queue' 2>/dev/null || true")
    system("pkill -f 'rails server' 2>/dev/null || true")
    system("pkill -f 'puma.*pit1' 2>/dev/null || true")
    sleep 3
    print_success "既存プロセスを停止しました"
  end

  FileUtils.rm_f("tmp/pids/server.pid")
  Dir.glob("tmp/pids/solid_queue*.pid").each { |f| FileUtils.rm_f(f) }

  answer = safe_gets("サーバを起動しますか？ (y/N): ")
  
  return unless answer && answer.downcase == 'y'

  # 環境変数の読み込み
  print_info "6. 環境変数の読み込み..."
  env_vars = load_env_vars
  
  required_vars = %w[ACTIVITYPUB_DOMAIN]
  missing_vars = required_vars.select { |var| env_vars[var].nil? || env_vars[var].empty? }
  
  if missing_vars.any?
    print_error "必須環境変数が設定されていません: #{missing_vars.join(', ')}"
    return
  end
  
  print_success "環境変数を読み込みました"
  print_info "ACTIVITYPUB_DOMAIN: #{env_vars['ACTIVITYPUB_DOMAIN']}"
  print_info "ACTIVITYPUB_PROTOCOL: #{env_vars['ACTIVITYPUB_PROTOCOL'] || 'http (default)'}"

  # サーバの起動
  print_info "7. サーバの起動..."
  
  system!("RAILS_ENV=development rails server -b 0.0.0.0 -p 3000 -d")
  print_success "Railsサーバを起動しました"

  system("RAILS_ENV=development nohup bin/jobs > log/solid_queue.log 2>&1 &")
  print_success "Solid Queueワーカーを起動しました"

  # 起動確認
  print_info "8. 起動確認中..."
  sleep 5

  server_ok = system("curl -s http://localhost:3000 > /dev/null 2>&1")
  if server_ok
    print_success "Railsサーバが応答しています"
  else
    print_warning "Railsサーバの応答確認に失敗しました"
  end

  # 最終結果表示
  puts ""
  print_header "セットアップ完了"
  print_success "letter が正常に起動しました"
  
  domain = env_vars['ACTIVITYPUB_DOMAIN'] || 'localhost'
  protocol = env_vars['ACTIVITYPUB_PROTOCOL'] || 'http'
  
  print_info "アクセス情報:"
  puts "  ローカルURL: http://localhost:3000"
  puts "  公開URL: #{protocol}://#{domain}" if domain != 'localhost'
  puts ""
  print_success "セットアップが正常に完了しました！"
end

# 2. サーバ起動・再起動
def cleanup_and_start
  puts ""
  print_header "letter 完全クリーンアップ＆再起動"
  print_info "実行時刻: #{Time.now}"

  # プロセス終了
  print_info "1. 関連プロセスの終了..."
  system("pkill -f 'solid.queue' 2>/dev/null || true")
  system("pkill -f 'rails server' 2>/dev/null || true")
  system("pkill -f 'puma.*pit1' 2>/dev/null || true")
  system("pkill -f 'bin/jobs' 2>/dev/null || true")
  sleep 3
  print_success "関連プロセスを終了しました"

  # 環境変数読み込み
  env_vars = load_env_vars
  unless env_vars['ACTIVITYPUB_DOMAIN']
    print_error ".envファイルが見つからないか、ACTIVITYPUB_DOMAINが設定されていません"
    return
  end

  print_success "環境変数を読み込みました"
  print_info "ACTIVITYPUB_DOMAIN: #{env_vars['ACTIVITYPUB_DOMAIN']}"
  print_info "ACTIVITYPUB_PROTOCOL: #{env_vars['ACTIVITYPUB_PROTOCOL']}"

  # PIDファイルクリーンアップ
  print_info "3. PIDファイルのクリーンアップ..."
  FileUtils.rm_f("tmp/pids/server.pid")
  Dir.glob("tmp/pids/solid_queue*.pid").each { |f| FileUtils.rm_f(f) }
  print_success "PIDファイルをクリーンアップしました"

  # データベースメンテナンス
  print_info "4. データベースのメンテナンス..."
  system("bin/rails db:migrate 2>/dev/null || true")

  # Rails サーバ起動
  print_info "5. Railsサーバを起動中..."
  domain = env_vars['ACTIVITYPUB_DOMAIN'] || 'localhost'
  protocol = env_vars['ACTIVITYPUB_PROTOCOL'] || 'http'
  
  begin
    system!("RAILS_ENV=development ACTIVITYPUB_DOMAIN='#{domain}' ACTIVITYPUB_PROTOCOL='#{protocol}' rails server -b 0.0.0.0 -p 3000 -d")
    print_success "Railsサーバをデーモンモードで起動しました"
  rescue => e
    print_error "Railsサーバ起動に失敗しました: #{e.message}"
    return
  end

  # Solid Queue 起動
  print_info "6. Solid Queueワーカーを起動中..."
  if system("RAILS_ENV=development ACTIVITYPUB_DOMAIN='#{domain}' ACTIVITYPUB_PROTOCOL='#{protocol}' nohup bin/jobs > log/solid_queue.log 2>&1 &")
    print_success "Solid Queueワーカーを起動しました"
  else
    print_warning "Solid Queueワーカーの起動に失敗しました"
  end

  # 起動確認
  print_info "7. 起動確認を実行中..."
  sleep 5

  if system("curl -s http://localhost:3000 >/dev/null 2>&1")
    print_success "Railsサーバが応答しています"
  else
    print_error "Railsサーバが応答していません"
  end

  puts ""
  print_header "起動完了"
  print_success "letter が正常に起動しました"
  
  print_info "アクセス情報:"
  puts "  サーバURL: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}"
  puts "  ローカルURL: http://localhost:3000"
  puts ""
  print_success "サーバの起動が正常に完了しました！"
end

# 3. ドメイン設定確認
def check_domain_config
  puts ""
  print_header "letter ドメイン設定確認"

  # 環境変数確認
  env_vars = load_env_vars
  if env_vars.any?
    print_info "環境設定:"
    puts "  ドメイン: #{env_vars['ACTIVITYPUB_DOMAIN']}"
    puts "  プロトコル: #{env_vars['ACTIVITYPUB_PROTOCOL']}"
    puts "  ベースURL: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}"
  else
    print_warning ".envファイルが見つかりません"
    return
  end

  # サーバ状態チェック
  puts ""
  print_info "サーバ状態チェック中..."

  rails_running = system("pgrep -f 'rails server' > /dev/null 2>&1")
  
  if rails_running
    print_success "サーバ状態: 動作中"
    
    # HTTP接続テスト
    if env_vars['ACTIVITYPUB_PROTOCOL'] && env_vars['ACTIVITYPUB_DOMAIN']
      server_response = `curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "#{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}" 2>/dev/null`.strip
      puts "  外部URL応答: #{server_response}"
    end
    
    local_response = `curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://localhost:3000" 2>/dev/null`.strip
    puts "  ローカル応答: #{local_response}"
    
    # ローカルユーザー表示
    puts ""
    print_info "ローカルユーザ:"
    begin
      users_code = "Actor.where(local: true).pluck(:username).each { |u| puts u }"
      local_users = run_rails_command(users_code).strip
      if local_users.empty?
        puts "  ローカルユーザが見つかりません"
      else
        local_users.lines.each { |user| puts "  - #{user.strip}" }
      end
    rescue
      puts "  データベースアクセスエラー"
    end
  else
    print_warning "サーバ状態: 停止中"
  end
end

# 4. ドメイン切り替え
def switch_domain
  puts ""
  print_header "letter ドメイン切り替え"
  
  print "新しいドメインを入力してください: "
  new_domain = gets.chomp
  
  # 制御文字を除去
  new_domain = new_domain.gsub(/[\x00-\x1F\x7F]/, '')
  
  if new_domain.empty?
    print_error "ドメインが入力されていません"
    return
  end
  
  print "プロトコルを入力してください (https/http, デフォルト: https): "
  new_protocol = gets.chomp
  
  # 制御文字を除去
  new_protocol = new_protocol.gsub(/[\x00-\x1F\x7F]/, '')
  new_protocol = "https" if new_protocol.empty?
  
  # 現在のドメイン取得
  env_vars = load_env_vars
  current_domain = env_vars['ACTIVITYPUB_DOMAIN']
  
  print_info "新しいドメイン: #{new_domain}"
  print_info "プロトコル: #{new_protocol}"
  print_info "現在のドメイン: #{current_domain}"
  
  puts ""
  print_warning "この操作により以下が実行されます:"
  puts "  1. .envファイルの更新"
  puts "  2. 現在のサーバの停止"
  puts "  3. データベース内のActor URLの更新"
  puts "  4. 新しいドメインでのサーバ再起動"
  puts ""
  answer = safe_gets("続行しますか? (y/N): ")
  
  return unless answer && answer.downcase == 'y'
  
  # .envファイルの更新
  print_info "ステップ 1/4: .envファイルの更新..."
  env_content = File.read(".env")
  env_content.gsub!(/^ACTIVITYPUB_DOMAIN=.*/, "ACTIVITYPUB_DOMAIN=#{new_domain}")
  env_content.gsub!(/^ACTIVITYPUB_PROTOCOL=.*/, "ACTIVITYPUB_PROTOCOL=#{new_protocol}")
  File.write(".env", env_content)
  print_success ".envファイルを更新しました"
  
  # サーバ停止
  print_info "ステップ 2/4: 現在のサーバを停止中..."
  system("pkill -f 'rails server' 2>/dev/null || true")
  system("pkill -f 'puma' 2>/dev/null || true")
  FileUtils.rm_f("tmp/pids/server.pid")
  print_success "サーバを停止しました"
  
  # データベース更新
  print_info "ステップ 3/4: データベース内のActor URLを更新中..."
  
  update_code = <<~RUBY
    new_base_url = "#{new_protocol}://#{new_domain}"
    local_actors = Actor.where(local: true)
    
    if local_actors.any?
      puts "#{local_actors.count}個のローカルアクターのドメインを更新します: #{new_base_url}"
      
      local_actors.each do |actor|
        actor.update!(
          ap_id: "\#{new_base_url}/users/\#{actor.username}",
          inbox_url: "\#{new_base_url}/users/\#{actor.username}/inbox",
          outbox_url: "\#{new_base_url}/users/\#{actor.username}/outbox",
          followers_url: "\#{new_base_url}/users/\#{actor.username}/followers",
          following_url: "\#{new_base_url}/users/\#{actor.username}/following"
        )
        puts "  ✓ \#{actor.username}を更新しました"
      end
      
      puts "すべてのローカルアクターの更新が完了しました!"
    else
      puts "ローカルアクターが見つかりません"
    end
  RUBY
  
  env_string = "ACTIVITYPUB_DOMAIN='#{new_domain}' ACTIVITYPUB_PROTOCOL='#{new_protocol}'"
  result = `#{env_string} bin/rails runner -e "#{update_code}" 2>/dev/null`
  puts result unless result.empty?
  
  print_success "データベースのURLを更新しました"
  
  # サーバ再起動
  print_info "ステップ 4/4: サーバを再起動中..."
  cleanup_and_start
  
  puts ""
  print_header "ドメイン切り替え完了"
  print_success "ドメイン切り替えが正常に完了しました!"
  print_info "確認情報:"
  puts "  サーバ: http://localhost:3000"
  puts "  ドメイン: #{new_domain}"
  puts "  プロトコル: #{new_protocol}"
end

# 5. アカウント作成・管理
def manage_accounts
  puts ""
  print_header "letter アカウント管理"
  
  print_info "このインスタンスは最大2個のローカルアカウントまで作成できます"
  puts ""
  
  # 現在のアカウント数を取得
  begin
    account_count_code = "puts Actor.where(local: true).count"
    account_count = run_rails_command(account_count_code).strip.to_i
  rescue
    print_error "データベースアクセスエラー"
    return
  end
  
  case account_count
  when 0
    print_info "現在のローカルアカウント数: 0/2"
    puts ""
    print_success "1個目のアカウントを作成します"
    create_account
  when 1
    print_info "現在のローカルアカウント数: 1/2"
    list_accounts_detailed
    puts ""
    print_success "2個目のアカウントを作成できます"
    puts ""
    print "新しいアカウントを作成しますか? (y/N): "
    answer = gets.chomp
    create_account if answer.downcase == 'y'
  when 2
    print_warning "現在のローカルアカウント数: 2/2 (上限に達しています)"
    list_accounts_detailed
    puts ""
    print_info "新しいアカウントを作成するには、既存のアカウントを削除する必要があります"
    puts ""
    puts "選択してください:"
    puts "1) アカウント1を削除して新しいアカウントを作成"
    puts "2) アカウント2を削除して新しいアカウントを作成"  
    puts "3) キャンセル"
    puts ""
    print "選択 (1-3): "
    choice = gets.chomp
    
    case choice
    when "1"
      if delete_account_by_number(1)
        puts ""
        print_info "新しいアカウントを作成します"
        create_account
      end
    when "2"
      if delete_account_by_number(2)
        puts ""
        print_info "新しいアカウントを作成します"
        create_account
      end
    when "3"
      print_info "操作をキャンセルしました"
    else
      print_error "無効な選択です"
    end
  else
    print_error "予期しないアカウント数です: #{account_count}"
  end
end

def list_accounts_detailed
  puts ""
  print_info "現在のローカルアカウント:"
  puts ""
  
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
  puts result unless result.strip.empty?
end

def create_account
  puts ""
  print_header "新しいアカウントの作成"
  puts ""
  
  print_info "アカウント情報を入力してください:"
  puts ""
  
  # ユーザ名を取得
  loop do
    username = safe_gets("ユーザ名 (英数字とアンダースコアのみ): ")
    
    return unless username
    
    if username.empty?
      print_error "ユーザ名は必須です"
      next
    end
    
    unless username.match?(/^[a-zA-Z0-9_]+$/)
      print_error "ユーザ名は英数字とアンダースコアのみ使用できます"
      print_info "入力された文字: '#{username}'"
      next
    end
    
    # ユーザ名重複チェック
    check_code = "puts Actor.exists?(username: '#{username}', local: true) ? 'exists' : 'available'"
    existing_check = run_rails_command(check_code).strip
    
    if existing_check == "exists"
      print_error "ユーザ名 '#{username}' は既に存在します"
      next
    end
    
    @username = username
    break
  end
  
  # パスワードを取得
  loop do
    password = safe_gets("パスワード (6文字以上): ")
    
    return unless password
    
    if password.length < 6
      print_error "パスワードは6文字以上である必要があります"
      next
    end
    
    password_confirm = safe_gets("パスワードを再入力: ")
    
    return unless password_confirm
    
    if password != password_confirm
      print_error "パスワードが一致しません"
      next
    end
    
    @password = password
    break
  end
  
  # 表示名を取得
  @display_name = safe_gets("表示名 (オプション): ") || ""
  
  # ノートを取得
  @note = safe_gets("プロフィール (オプション): ") || ""
  
  puts ""
  print_info "入力内容を確認してください:"
  puts "  ユーザ名: #{@username}"
  puts "  表示名: #{@display_name.empty? ? '未設定' : @display_name}"
  puts "  プロフィール: #{@note.empty? ? '未設定' : @note}"
  puts ""
  
  answer = safe_gets("この内容でアカウントを作成しますか? (y/N): ")
  
  return unless answer && answer.downcase == 'y'
  
  puts ""
  print_info "アカウントを作成中..."
  
  # アカウント作成
  creation_code = <<~RUBY
    begin
      actor = Actor.new(
        username: '#{@username}',
        password: '#{@password}',
        display_name: '#{@display_name}',
        note: '#{@note}',
        local: true,
        discoverable: true,
        manually_approves_followers: false
      )
      
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
  
  result = run_rails_command(creation_code)
  lines = result.strip.lines
  status = lines[0]&.strip
  detail = lines[1]&.strip
  
  if status == "success"
    env_vars = load_env_vars
    print_success "アカウントが正常に作成されました!"
    puts ""
    print_info "アカウント詳細:"
    puts "  ユーザ名: #{@username}"
    puts "  表示名: #{@display_name.empty? ? '未設定' : @display_name}"
    puts "  ActivityPub ID: #{env_vars['ACTIVITYPUB_PROTOCOL']}://#{env_vars['ACTIVITYPUB_DOMAIN']}/users/#{@username}"
    puts "  WebFinger: @#{@username}@#{env_vars['ACTIVITYPUB_DOMAIN']}"
  else
    print_error "アカウント作成に失敗しました: #{detail}"
  end
end

# 6. アカウント削除
def delete_account
  puts ""
  print_header "アカウント削除"
  
  print "削除するアカウントのユーザ名またはIDを入力してください: "
  identifier = gets.chomp
  
  # 制御文字を除去
  identifier = identifier.gsub(/[\x00-\x1F\x7F]/, '')
  
  if identifier.empty?
    print_error "ユーザ名またはIDが入力されていません"
    return
  end
  
  print_info "アカウントを削除しています: #{identifier}"
  puts ""
  
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
  lines = result.strip.lines
  
  return false if lines[0]&.strip == 'invalid'
  
  username = lines[0]&.strip
  display_name = lines[1]&.strip
  account_id = lines[2]&.strip
  
  puts ""
  print_warning "削除対象のアカウント:"
  puts "  ユーザ名: #{username}"
  puts "  表示名: #{display_name}"
  puts ""
  print_error "この操作は取り消すことができません!"
  puts ""
  
  print "本当にこのアカウントを削除しますか? 'DELETE' と入力してください: "
  confirm = gets.chomp
  
  return false unless confirm == "DELETE"
  
  puts ""
  print_info "アカウントを削除中..."
  
  delete_account_by_identifier(account_id)
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
      
      unless actor
        puts 'not_found'
        puts 'アカウントが見つかりません'
        exit
      end
      
      puts 'found'
      puts "ID: \#{actor.id}"
      puts "ユーザ名: \#{actor.username}"
      puts "表示名: \#{actor.display_name || '未設定'}"
      puts "作成日: \#{actor.created_at.strftime('%Y-%m-%d %H:%M')}"
      
      # 投稿数などの統計情報
      posts_count = ActivityPubObject.where(actor_id: actor.id, object_type: 'Note').count
      following_count = Follow.where(actor_id: actor.id).count
      followers_count = Follow.where(target_actor_id: actor.id).count
      
      puts "投稿数: \#{posts_count}"
      puts "フォロー数: \#{following_count}"
      puts "フォロワー数: \#{followers_count}"
      
    rescue => e
      puts 'error'
      puts e.message
    end
  RUBY
  
  info_result = run_rails_command(account_info_code)
  info_lines = info_result.strip.lines
  status = info_lines[0]&.strip
  
  case status
  when "not_found"
    detail = info_lines[1]&.strip
    print_error detail
    
    print_info "既存のローカルユーザ一覧:"
    list_code = <<~RUBY
      actors = Actor.where(local: true)
      if actors.any?
        actors.each { |a| puts "  - ID: \#{a.id}, ユーザ名: \#{a.username} (\#{a.display_name || '表示名未設定'})" }
      else
        puts '  ローカルユーザがありません。'
      end
    RUBY
    
    local_users = run_rails_command(list_code)
    puts local_users
    return false
  when "found"
    puts ""
    print_warning "削除対象のアカウント詳細:"
    info_lines[1..-1].each { |line| puts "  #{line.strip}" }
    puts ""
    
    print_error "⚠️ 重要な警告 ⚠️"
    puts "この操作により以下のデータが完全に削除されます:"
    puts "  • アカウント情報（プロフィール、設定等）"
    puts "  • 投稿したすべての内容"
    puts "  • フォロー・フォロワー関係"
    puts "  • お気に入り、ブックマーク"
    puts "  • 通知履歴"
    puts "  • OAuthトークン"
    puts "  • その他すべての関連データ"
    puts ""
    print_error "この操作は取り消すことができません！"
    puts ""
    
    # 最終確認
    answer1 = safe_gets("本当にこのアカウントを削除しますか？ (yes/no): ")
    return false unless answer1&.downcase == "yes"
    
    puts ""
    print_warning "最終確認です。"
    answer2 = safe_gets("確実に削除を実行するため 'DELETE' と正確に入力してください: ")
    return false unless answer2 == "DELETE"
    
    puts ""
    print_info "アカウントを削除しています..."
    
    # 実際の削除処理
    deletion_code = <<~RUBY
      begin
        # アカウント再取得
        if '#{identifier}'.match?(/^\\d+$/)
          actor = Actor.find_by(id: '#{identifier}')
        else
          actor = Actor.find_by(username: '#{identifier}', local: true)
        end
        
        unless actor
          puts 'not_found'
          exit
        end
        
        actor_id = actor.id
        username = actor.username
        
        # 直接SQL削除で全ての依存レコードを削除
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
        
        # OAuthトークンも削除
        begin
          Doorkeeper::AccessToken.where(resource_owner_id: actor_id).delete_all
          Doorkeeper::AccessGrant.where(resource_owner_id: actor_id).delete_all
        rescue
          # Doorkeeperテーブルがない場合はスキップ
        end
        
        # 最後にアカウント削除
        ActiveRecord::Base.connection.execute("DELETE FROM actors WHERE id = \#{actor_id}")
        
        puts 'success'
        puts "アカウント '\#{username}' とすべての関連レコードが正常に削除されました"
        
      rescue => e
        puts 'error'
        puts e.message
      end
    RUBY
    
    result = run_rails_command(deletion_code)
    result_lines = result.strip.lines
    result_status = result_lines[0]&.strip
    
    if result_status == "success"
      print_success result_lines[1]&.strip
      
      # 残りアカウント数表示
      remaining_code = "puts Actor.where(local: true).count"
      remaining_count = run_rails_command(remaining_code).strip
      print_info "残りのローカルアカウント数: #{remaining_count}"
      return true
    else
      detail = result_lines[1..-1]&.join("\n")
      print_error "削除に失敗しました: #{detail}"
      return false
    end
  when "error"
    detail = info_lines[1..-1]&.join("\n")
    print_error "アカウント情報取得中にエラーが発生しました:"
    puts detail
    return false
  else
    print_error "予期しない結果:"
    puts info_result
    return false
  end
end

# 7. OAuthトークン生成
def create_oauth_token
  puts ""
  print_header "letter OAuth トークン生成"
  puts ""
  
  print_info "このスクリプトはAPIアクセス用のOAuthトークンを生成します"
  puts ""
  
  # ユーザ名入力
  loop do
    print "ユーザ名を入力してください: "
    username = gets.chomp
    
    # 制御文字を除去
    username = username.gsub(/[\x00-\x1F\x7F]/, '')
    
    if username.empty?
      print_error "ユーザ名は必須です"
      next
    end
    
    unless username.match?(/^[a-zA-Z0-9_]+$/)
      print_error "ユーザ名は英数字とアンダースコアのみ使用できます"
      print_info "入力された文字: '#{username}'"
      next
    end
    
    # ユーザ存在チェック
    user_check_code = "puts Actor.exists?(username: '#{username}', local: true) ? 'exists' : 'not_found'"
    user_check = run_rails_command(user_check_code).strip
    
    if user_check == "not_found"
      print_error "ユーザ '#{username}' が見つかりません"
      print_info "既存のローカルユーザを確認してください"
      puts ""
      print_info "既存のローカルユーザ一覧:"
      
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
      puts ""
      next
    end
    
    @token_username = username
    break
  end
  
  puts ""
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
  puts ""
  
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
  
  if status == "success" || status == "exists"
    if status == "success"
      print_success message
    else
      print_warning message
    end
    
    puts ""
    print_header "生成されたOAuthトークン情報"
    puts ""
    print_info "アプリケーション詳細:"
    puts "  名前: #{token_data['app_name']}"
    puts "  クライアントID: #{token_data['client_id']}"
    puts "  クライアントシークレット: #{token_data['client_secret']}"
    puts ""
    print_info "🔑 アクセストークン（重要！）:"
    puts "  #{token_data['token']}"
    puts ""
    print_info "トークン詳細:"
    puts "  スコープ: #{token_data['scopes']}"
    puts "  ユーザ: #{token_data['username']}"
    puts "  作成日時: #{token_data['created_at']}"
    puts ""
    print_header "API使用例"
    puts ""
    print_info "📋 よく使用されるAPIコマンド（コピーして使用してください）:"
    puts ""
    puts "# アカウント情報確認"
    puts "curl -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/accounts/verify_credentials\""
    puts ""
    puts "# 投稿作成"
    puts "curl -X POST \\"
    puts "     -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts "     -H \"Content-Type: application/json\" \\"
    puts "     -d '{\"status\":\"Hello from API!\",\"visibility\":\"public\"}' \\"
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/statuses\""
    puts ""
    puts "# アバター画像設定"
    puts "curl -X PATCH \\"
    puts "     -H \"Authorization: Bearer #{token_data['token']}\" \\"
    puts "     -F \"avatar=@/path/to/image.png\" \\"
    puts "     \"#{token_data['protocol']}://#{token_data['domain']}/api/v1/accounts/update_credentials\""
    puts ""
    print_warning "⚠️ このトークンは秘密情報です。安全に保管してください。"
    puts ""
    print_success "OAuthトークンの生成が完了しました！"
  else
    print_error message
  end
end

# 8. VAPIDキー生成
def generate_vapid_keys
  puts ""
  print_header "VAPID キーペア生成スクリプト"
  puts ""
  
  begin
    # opensslコマンドを使用してVAPIDキーを生成
    print_info "1. 秘密鍵を生成中..."
    
    # 一時ファイル名
    private_key_file = "/tmp/vapid_private_key_#{Random.rand(10000)}.pem"
    public_key_file = "/tmp/vapid_public_key_#{Random.rand(10000)}.pem"
    
    # 秘密鍵を生成 (P-256楕円曲線)
    unless system("openssl ecparam -genkey -name prime256v1 -noout -out #{private_key_file} 2>/dev/null")
      raise "秘密鍵の生成に失敗しました"
    end
    
    # 公開鍵を生成
    print_info "2. 公開鍵を生成中..."
    unless system("openssl ec -in #{private_key_file} -pubout -out #{public_key_file} 2>/dev/null")
      raise "公開鍵の生成に失敗しました"
    end
    
    # Base64エンコード（URLセーフ）でキーを抽出
    print_info "3. キーをBase64エンコード中..."
    
    # Rubyの標準ライブラリを使用してより確実にキーを抽出
    require 'openssl'
    
    # PEMファイルから秘密鍵を読み込み
    private_key_pem = File.read(private_key_file)
    private_key = OpenSSL::PKey::EC.new(private_key_pem)
    
    # 秘密鍵のバイナリデータを取得（32バイト）
    private_key_bn = private_key.private_key
    private_key_bytes = private_key_bn.to_s(2).rjust(32, "\x00")
    private_key_b64 = Base64.urlsafe_encode64(private_key_bytes).gsub('=', '')
    
    # 公開鍵のバイナリデータを取得（64バイト、0x04プレフィックスを除く）
    public_key_point = private_key.public_key
    public_key_bytes = public_key_point.to_bn.to_s(2)[1..-1]  # 最初の0x04バイトを除去
    public_key_b64 = Base64.urlsafe_encode64(public_key_bytes).gsub('=', '')
    
    # 一時ファイルを削除
    File.delete(private_key_file) if File.exist?(private_key_file)
    File.delete(public_key_file) if File.exist?(public_key_file)
    
    if private_key_b64.empty? || public_key_b64.empty?
      raise "キーの抽出に失敗しました"
    end
    
    puts ""
    print_header "生成されたVAPIDキーペア"
    puts "VAPID_PUBLIC_KEY=#{public_key_b64}"
    puts "VAPID_PRIVATE_KEY=#{private_key_b64}"
    puts ""
    
    print_info ".envファイルへの追加"
    puts "以下の行を .env ファイルに追加または更新してください："
    puts ""
    puts "VAPID_PUBLIC_KEY=#{public_key_b64}"
    puts "VAPID_PRIVATE_KEY=#{private_key_b64}"
    puts ""
    
    # 既存の.envファイルがある場合、更新を提案
    if File.exist?(".env")
      response = safe_gets("既存の.envファイルを更新しますか？ (y/N): ")
      
      if response && response.downcase == 'y'
        # バックアップを作成
        FileUtils.cp(".env", ".env.backup")
        print_info ".envファイルのバックアップを作成しました: .env.backup"
        
        # 既存のVAPIDキーを削除して新しいキーを追加
        env_content = File.read(".env")
        env_content.gsub!(/^VAPID_PUBLIC_KEY=.*\n?/, '')
        env_content.gsub!(/^VAPID_PRIVATE_KEY=.*\n?/, '')
        
        # ファイルの最後に新しいキーを追加
        env_content = env_content.rstrip + "\n"
        env_content += "VAPID_PUBLIC_KEY=#{public_key_b64}\n"
        env_content += "VAPID_PRIVATE_KEY=#{private_key_b64}\n"
        
        File.write(".env", env_content)
        print_success ".envファイルを更新しました"
      end
    end
    
    puts ""
    print_header "注意事項"
    puts "- VAPIDキーを変更すると、既存のプッシュ通知サブスクリプションは無効になります"
    puts "- サーバを再起動して新しいキーを適用してください"
    puts "- これらのキーは安全に保管してください"
    puts ""
    print_success "VAPIDキーの生成が完了しました！"
    
  rescue => e
    print_error "VAPIDキー生成に失敗しました: #{e.message}"
    print_info "詳細: #{e.backtrace.first}" if e.backtrace
    
    # 一時ファイルをクリーンアップ
    [private_key_file, public_key_file].each do |file|
      File.delete(file) if file && File.exist?(file)
    end
  end
end

# 9. Cloudflare R2 移行
def migrate_to_r2
  puts ""
  print_header "letter - Cloudflare R2 移行"
  puts ""
  
  env_vars = load_env_vars
  
  # R2が有効かチェック
  unless env_vars['S3_ENABLED'] == "true"
    print_error "Cloudflare R2が無効になっています"
    print_info "移行を実行するには、.envファイルでS3_ENABLED=trueに設定してください"
    return
  end
  
  # 必要なR2設定をチェック
  missing_config = []
  %w[S3_ENDPOINT S3_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY].each do |key|
    missing_config << key if env_vars[key].nil? || env_vars[key].empty?
  end
  
  if missing_config.any?
    print_error "以下の設定が不足しています: #{missing_config.join(', ')}"
    print_info "設定を確認してから再度実行してください"
    return
  end
  
  print_success "Cloudflare R2設定確認完了"
  puts ""
  print_info "エンドポイント: #{env_vars['S3_ENDPOINT']}"
  print_info "バケット: #{env_vars['S3_BUCKET']}"
  puts ""
  
  # 移行統計を取得
  print_info "現在のファイル状況を確認中..."
  
  stats_code = <<~RUBY
    total_local = ActiveStorage::Blob.where(service_name: ['local', nil]).count
    total_r2 = ActiveStorage::Blob.where(service_name: 'cloudflare_r2').count
    
    puts "total_local|\#{total_local}"
    puts "total_r2|\#{total_r2}"
  RUBY
  
  result = run_rails_command(stats_code)
  
  local_total = result.lines.find { |l| l.start_with?('total_local|') }&.split('|', 2)&.last&.strip&.to_i || 0
  r2_total = result.lines.find { |l| l.start_with?('total_r2|') }&.split('|', 2)&.last&.strip&.to_i || 0
  
  puts ""
  print_info "ファイル状況:"
  puts "  ローカル合計: #{local_total}"
  puts "  R2合計: #{r2_total}"
  puts ""
  
  if local_total == 0
    print_success "移行対象のローカルファイルはありません"
    return
  end
  
  # 移行を確認
  print "これらのファイルをCloudflare R2に移行しますか？ (y/N): "
  confirmation = gets.chomp
  
  return unless confirmation.downcase == 'y'
  
  puts ""
  print "バッチサイズを入力してください (10-200, デフォルト: 50): "
  batch_size = gets.chomp
  batch_size = batch_size.empty? ? 50 : batch_size.to_i
  
  if batch_size < 10 || batch_size > 200
    print_error "バッチサイズは10から200の間で指定してください"
    return
  end
  
  puts ""
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
    
    puts ""
    if status == "success"
      print_success message
      
      # 最終統計を取得
      final_result = run_rails_command(stats_code)
      final_local = final_result.lines.find { |l| l.start_with?('total_local|') }&.split('|', 2)&.last&.strip&.to_i || 0
      final_r2 = final_result.lines.find { |l| l.start_with?('total_r2|') }&.split('|', 2)&.last&.strip&.to_i || 0
      
      puts ""
      print_info "移行後の状況:"
      puts "  ローカル: #{final_local}"
      puts "  R2: #{final_r2}"
    else
      print_error message
    end
  else
    print_error "移行結果の解析に失敗しました"
  end
  
  puts ""
  print_header "Cloudflare R2 移行完了"
end

def safe_gets(prompt = "")
  print prompt unless prompt.empty?
  input = gets
  return nil if input.nil?
  input.chomp.gsub(/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/, '')
end

def countdown_return(seconds, message = "メニューに戻ります")
  print_info "#{message}... "
  seconds.downto(1) do |i|
    print "#{i} "
    $stdout.flush
    sleep 1
  end
  puts ""
end

def main_loop
  FileUtils.chdir APP_ROOT do
    loop do
      system("clear") || system("cls")
      show_logo
      show_menu
      
      choice = safe_gets("選択してください (0-9): ")
      
      # 入力が中断された場合の処理
      if choice.nil?
        puts ""
        print_info "入力が中断されました。終了します。"
        break
      end
      
      case choice
      when "1"
        setup_new_installation
      when "2"
        cleanup_and_start
      when "3"
        check_domain_config
      when "4"
        switch_domain
      when "5"
        manage_accounts
      when "6"
        delete_account
      when "7"
        create_oauth_token
      when "8"
        generate_vapid_keys
      when "9"
        migrate_to_r2
      when "0"
        puts ""
        print_success "letter管理スクリプトを終了します"
        break
      else
        puts ""
        print_error "無効な選択です。0-9の数字を入力してください。"
        puts ""
        countdown_return(2)
        next
      end
      
      unless choice == "0"
        puts ""
        puts ""
        # OAuthトークン生成とドメイン設定確認の場合は手動復帰、その他は自動復帰
        if choice == "7" || choice == "3"
          safe_gets("Enterキーを押してメニューに戻ります...")
        else
          countdown_return(3, "操作が完了しました。メニューに戻ります")
        end
      end
    end
  end
end

# スクリプト実行
if __FILE__ == $0
  main_loop
end