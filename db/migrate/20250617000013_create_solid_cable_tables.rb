# frozen_string_literal: true

class CreateSolidCableTables < ActiveRecord::Migration[8.0]
  def change
    current_db = ActiveRecord::Base.connection_db_config.name
    return unless current_db == "primary" || current_db == "cable"
    
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end