# frozen_string_literal: true

class CreateTagUsageHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :tag_usage_histories, id: :integer do |t|
      t.references :tag, null: false, foreign_key: true, type: :integer
      t.date :date, null: false
      t.integer :uses, default: 0
      t.integer :accounts, default: 0
    end
    add_index :tag_usage_histories, %i[tag_id date], unique: true
  end
end
