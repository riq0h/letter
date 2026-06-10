# frozen_string_literal: true

class CreateSolidQueueRecurringTables < ActiveRecord::Migration[8.0]
  # 2025-06の初期構築時(20250617000010)のSolid Queueスキーマには
  # recurring機能のテーブルが含まれておらず、recurring.ymlにタスクを
  # 定義するとsupervisorが起動できない。gem 1.1.5のqueue_schema.rbと
  # 同一の定義で追加する
  def change
    current_db = ActiveRecord::Base.connection_db_config.name
    return unless %w[primary queue].include?(current_db)

    create_table :solid_queue_recurring_tasks, if_not_exists: true do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :schedule, null: false
      t.string :command, limit: 2048
      t.string :class_name
      t.text :arguments
      t.string :queue_name
      t.integer :priority, default: 0
      t.boolean :static, default: true, null: false, index: true
      t.text :description

      t.timestamps
    end

    create_table :solid_queue_recurring_executions, if_not_exists: true do |t|
      t.references :job, null: false, index: { unique: true },
                         foreign_key: { to_table: :solid_queue_jobs, on_delete: :cascade }
      t.string :task_key, null: false
      t.datetime :run_at, null: false
      t.datetime :created_at, null: false

      t.index %i[task_key run_at], unique: true
    end
  end
end
