# frozen_string_literal: true

class CreateCoreActivitypubTables < ActiveRecord::Migration[8.0]
  def change
    # コアアクターテーブル（ユーザ/アカウント）
    create_table :actors, id: :integer do |t|
      # 基本ユーザ情報
      t.string :username, null: false
      t.string :domain, index: true
      t.string :display_name
      t.text :note
      
      # ActivityPub URL
      t.string :ap_id, null: false, index: { unique: true }
      t.string :inbox_url, null: false
      t.string :outbox_url, null: false
      t.string :shared_inbox_url
      t.string :followers_url
      t.string :following_url
      t.string :featured_url
      
      # 暗号化キー
      t.text :public_key
      t.text :private_key
      
      # アクターメタデータ
      t.boolean :local, default: false, null: false, index: true
      t.boolean :locked, default: false
      t.boolean :bot, default: false
      t.boolean :suspended, default: false
      t.boolean :admin, default: false
      
      # プロフィールフィールド
      t.text :fields
      
      # ソーシャル数
      t.integer :followers_count, default: 0
      t.integer :following_count, default: 0
      t.integer :posts_count, default: 0
      
      # ActivityPub準拠
      t.text :raw_data
      t.string :actor_type, default: 'Person'
      t.boolean :discoverable, default: true
      t.boolean :manually_approves_followers, default: false
      
      # 認証（ローカルユーザ用）
      t.string :password_digest
      
      # ユーザ設定と環境設定
      t.json :settings, default: '{}'
      
      t.timestamps
    end

    add_index :actors, [:username, :domain], unique: true
    add_index :actors, :username

    # ActivityPubオブジェクトテーブル（投稿/コンテンツ）
    create_table :objects, id: :string do |t|
      # ActivityPubメタデータ
      t.string :ap_id, null: false, index: { unique: true }
      t.string :object_type, null: false, index: true
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      
      # コンテンツ
      t.text :content
      t.text :content_plaintext
      t.text :summary
      t.string :url
      t.string :language
      
      
      # コンテンツメタデータ
      t.boolean :sensitive, default: false
      t.string :visibility, default: 'public', index: true
      t.text :raw_data
      t.datetime :published_at, index: true
      
      # ローカル/リモートフラグ
      t.boolean :local, default: false, index: true
      
      # ピン専用フラグ（ピン用にのみ取得され、タイムラインから除外されるコンテンツ用）
      t.boolean :is_pinned_only, default: false, index: true
      
      # リレー追跡（リレー経由で受信された投稿用）
      t.references :relay, foreign_key: true, type: :integer, null: true, index: true
      
      # Social counts
      t.integer :replies_count, default: 0
      t.integer :reblogs_count, default: 0
      t.integer :favourites_count, default: 0
      
      # 編集追跡
      t.datetime :edited_at, index: true
      
      t.timestamps
    end

    # ActivityPubアクティビティテーブル
    create_table :activities, id: :string do |t|
      # ActivityPubメタデータ
      t.string :ap_id, null: false, index: { unique: true }
      t.string :activity_type, null: false, index: true
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      
      # アクティビティターゲット
      t.string :object_ap_id, index: true
      t.string :target_ap_id, index: true
      
      # コンテンツとメタデータ
      t.text :raw_data
      t.datetime :published_at, index: true
      t.boolean :local, default: false, index: true
      
      # 処理状況（重複防止用）
      t.boolean :processed, default: false, index: true
      t.datetime :processed_at
      
      # 配信追跡
      t.boolean :delivered, default: false
      t.datetime :delivered_at
      t.integer :delivery_attempts, default: 0
      t.text :last_delivery_error
      
      t.timestamps
    end

    # ステータス編集履歴テーブル
    create_table :status_edits, id: :string do |t|
      t.references :object, foreign_key: true, type: :string, null: false, index: true
      
      # 編集時のコンテンツスナップショット
      t.text :content
      t.text :content_plaintext
      t.text :summary
      t.boolean :sensitive, default: false
      t.string :language
      
      # 編集時のメディア添付
      t.json :media_ids
      t.json :media_descriptions
      
      # 編集時の投票データ
      t.json :poll_options
      
      t.datetime :created_at, null: false, index: true
    end

    add_index :status_edits, [:object_id, :created_at]

    # ActivityPubリレーテーブル
    create_table :relays do |t|
      t.string :inbox_url, null: false, index: { unique: true }
      t.string :state, default: 'idle', null: false, index: true
      t.string :follow_activity_id, index: true
      t.datetime :followed_at
      t.text :last_error
      t.integer :delivery_attempts, default: 0
      
      t.timestamps
    end

    # リンクプレビュー（OGP）テーブル
    create_table :link_previews do |t|
      t.string :url, null: false, index: { unique: true }
      t.string :title
      t.text :description
      t.string :image
      t.string :site_name
      t.string :preview_type, default: 'website'
      
      t.timestamps
    end

    # パフォーマンス最適化のための複合インデックス
    add_index :objects, [:object_type, :visibility, :published_at], 
              name: 'index_objects_on_object_type_visibility_published_at'
    add_index :activities, [:activity_type, :processed, :created_at], 
              name: 'index_activities_on_activity_type_processed_created_at'
  end
end
