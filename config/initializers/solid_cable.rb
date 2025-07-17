# frozen_string_literal: true

if Rails.env.development? || Rails.env.production?
  
  # アプリケーション初期化後にcableデータベースをセットアップ
  Rails.application.config.after_initialize do
    begin
      # cableデータベースに接続
      ActiveRecord::Base.establish_connection(:cable)
      
      # テーブルが存在しない場合のみ作成
      unless ActiveRecord::Base.connection.table_exists?('solid_cable_messages')
        Rails.logger.info "📡 Creating Solid Cable tables"
        
        cable_schema_path = Rails.root.join('db/cable_schema.rb')
        if File.exist?(cable_schema_path)
          load cable_schema_path
          Rails.logger.info "✅ Solid Cable database initialized from schema"
        else
          Rails.logger.warn "⚠️  Cable schema file not found. Please run: bundle exec rails solid_cable:install"
        end
      end
      
    rescue ActiveRecord::NoDatabaseError
      # データベースファイルが存在しない場合は作成
      Rails.logger.info "📁 Creating cable database file"
      ActiveRecord::Tasks::DatabaseTasks.create(ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: 'cable').first)
      
      # テーブル作成
      ActiveRecord::Base.establish_connection(:cable)
      
      cable_schema_path = Rails.root.join('db/cable_schema.rb')
      if File.exist?(cable_schema_path)
        load cable_schema_path
        Rails.logger.info "✅ Solid Cable database created and initialized from schema"
      else
        Rails.logger.warn "⚠️  Cable schema file not found. Please run: bundle exec rails solid_cable:install"
      end
      
    rescue => e
      Rails.logger.warn "⚠️  Solid Cable setup failed: #{e.message}"
      
    ensure
      # メインデータベースに接続を戻す
      ActiveRecord::Base.establish_connection(:primary)
    end
  end
end