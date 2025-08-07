# frozen_string_literal: true

class CreateSystemFeatures < ActiveRecord::Migration[8.0]
  def change
    # User limits and quotas
    create_table :user_limits, id: :integer do |t|
      t.references :actor, foreign_key: true, type: :integer, null: false, index: { unique: true }
      
      # Limit types and values
      t.string :limit_type, null: false
      t.integer :limit_value, null: false
      t.integer :current_usage, default: 0
      t.datetime :reset_at
      t.boolean :enabled, default: true, null: false
      
      t.timestamps
    end

    add_index :user_limits, [:actor_id, :limit_type], unique: true
    add_index :user_limits, :enabled

    # Content filters
    create_table :filters, id: :integer do |t|
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.string :title, null: false
      t.text :context, null: false # JSON array: ['home', 'notifications', 'public', 'thread', 'account']
      t.datetime :expires_at
      t.string :filter_action, default: 'warn', null: false # 'warn' or 'hide'
      
      t.timestamps
    end

    # Filter keywords
    create_table :filter_keywords, id: :integer do |t|
      t.references :filter, foreign_key: true, type: :integer, null: false, index: true
      t.string :keyword, null: false
      t.boolean :whole_word, default: false, null: false
      
      t.timestamps
    end

    # Filter statuses (specific status filtering)
    create_table :filter_statuses, id: :integer do |t|
      t.references :filter, foreign_key: true, type: :integer, null: false, index: true
      t.string :status_id, null: false, index: true
      
      t.timestamps
    end

    add_index :filter_keywords, [:filter_id, :keyword], unique: true
    add_index :filter_statuses, [:filter_id, :status_id], unique: true
    add_foreign_key :filter_statuses, :objects, column: :status_id, primary_key: :id

    # Push notification subscriptions
    create_table :web_push_subscriptions, id: :integer do |t|
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.text :data # JSON for alert types and other settings
      
      t.timestamps
    end

    add_index :web_push_subscriptions, [:actor_id, :endpoint], unique: true

    # Markers (timeline position tracking) - replaces Redis cache with database
    create_table :markers, id: :integer do |t|
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.string :timeline, null: false # 'home', 'notifications'
      t.string :last_read_id, null: false
      t.integer :version, default: 1, null: false
      
      t.timestamps
    end

    add_index :markers, [:actor_id, :timeline], unique: true

    # Announcements (system-wide announcements)
    create_table :announcements, id: :integer do |t|
      t.text :content, null: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.boolean :published, default: false, null: false
      t.boolean :all_day, default: false, null: false
      t.datetime :published_at
      t.json :mentions # Array of mentioned accounts
      t.json :statuses # Array of linked statuses
      t.json :tags # Array of linked tags
      t.json :emojis # Array of custom emojis
      
      t.timestamps
    end

    # Announcement reactions
    create_table :announcement_reactions, id: :integer do |t|
      t.references :announcement, foreign_key: true, type: :integer, null: false, index: true
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.string :name, null: false # Emoji name
      
      t.timestamps
    end

    add_index :announcement_reactions, [:announcement_id, :actor_id, :name], unique: true

    # Announcement dismissals
    create_table :announcement_dismissals, id: :integer do |t|
      t.references :announcement, foreign_key: true, type: :integer, null: false, index: true
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      
      t.timestamps
    end

    add_index :announcement_dismissals, [:announcement_id, :actor_id], unique: true

    # Reports (content moderation)
    create_table :reports, id: :integer do |t|
      t.references :reporter, foreign_key: { to_table: :actors }, type: :integer, null: false, index: true
      t.references :target_account, foreign_key: { to_table: :actors }, type: :integer, null: false, index: true
      t.json :status_ids # Array of reported status IDs
      t.text :comment
      t.string :category, default: 'other' # spam, legal, violation, other
      t.boolean :forwarded, default: false
      t.boolean :action_taken, default: false
      t.datetime :action_taken_at
      t.json :rule_ids # Array of violated rule IDs
      
      t.timestamps
    end

    # Polls
    create_table :polls, id: :integer do |t|
      t.string :object_id, null: false, index: true # Associated status
      t.datetime :expires_at, null: false
      t.boolean :multiple, default: false, null: false
      t.integer :votes_count, default: 0, null: false
      t.integer :voters_count, default: 0
      t.json :options, null: false # Array of option objects
      t.boolean :hide_totals, default: false, null: false
      
      t.timestamps
    end

    add_foreign_key :polls, :objects, column: :object_id, primary_key: :id

    # Poll votes
    create_table :poll_votes, id: :integer do |t|
      t.references :poll, foreign_key: true, type: :integer, null: false, index: true
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.integer :choice, null: false # Option index
      
      t.timestamps
    end

    add_index :poll_votes, [:poll_id, :actor_id, :choice], unique: true

    # Scheduled statuses
    create_table :scheduled_statuses, id: :integer do |t|
      t.references :actor, foreign_key: true, type: :integer, null: false, index: true
      t.datetime :scheduled_at, null: false
      t.json :params, null: false # Status parameters
      t.json :media_attachment_ids # Array of media IDs
      
      t.timestamps
    end

    add_index :scheduled_statuses, :scheduled_at

    # Unavailable servers (410 Gone tracking)
    create_table :unavailable_servers, id: :integer do |t|
      t.string :domain, null: false
      t.string :reason, default: 'gone', null: false # 'gone', 'timeout', 'error'
      t.datetime :first_error_at, null: false
      t.datetime :last_error_at, null: false
      t.integer :error_count, default: 1, null: false
      t.text :last_error_message
      t.boolean :auto_detected, default: true, null: false
      
      t.timestamps
    end

    add_index :unavailable_servers, :domain, unique: true
    add_index :unavailable_servers, :reason
    add_index :unavailable_servers, :last_error_at

    # Instance configuration (database-backed settings)
    create_table :instance_configs, id: :integer do |t|
      t.string :config_key, null: false
      t.text :value, null: false
      
      t.timestamps
    end
    
    add_index :instance_configs, :config_key, unique: true
  end
end