# frozen_string_literal: true

class CreateHomeFeedEntries < ActiveRecord::Migration[8.0]
  def change
    current_db = ActiveRecord::Base.connection_db_config.name
    return unless current_db == 'primary' || current_db == 'cache'

    create_table :home_feed_entries do |t|
      t.string :sort_id, null: false
      t.string :object_id, null: false
      t.integer :reblog_id
      t.integer :actor_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :home_feed_entries, :sort_id, order: :desc, unique: true, name: 'idx_home_feed_sort_id'
    add_index :home_feed_entries, :object_id, name: 'idx_home_feed_object_id'
    add_index :home_feed_entries, :reblog_id, name: 'idx_home_feed_reblog_id'
  end
end
