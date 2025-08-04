# frozen_string_literal: true

class CreateSolidCacheTables < ActiveRecord::Migration[8.0]
  def change
    current_db = ActiveRecord::Base.connection_db_config.name
    return unless current_db == "primary" || current_db == "cache"
    
    create_table :solid_cache_entries do |t|
      t.binary :key, null: false, limit: 1024
      t.binary :value, null: false, limit: 536870912
      t.datetime :created_at, null: false
      t.bigint :key_hash, null: false
      t.bigint :byte_size, null: false

      t.index :key_hash, unique: true
      t.index :byte_size
      t.index [:key_hash, :byte_size]
    end
  end
end