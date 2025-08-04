# frozen_string_literal: true

class CreateSolidQueueTables < ActiveRecord::Migration[8.0]
  def change
    current_db = ActiveRecord::Base.connection_db_config.name
    return unless current_db == "primary" || current_db == "queue"
    create_table :solid_queue_jobs do |t|
      t.string :queue_name, null: false, index: { name: "index_solid_queue_jobs_for_polling" }
      t.string :class_name, null: false
      t.text :arguments
      t.integer :priority, default: 0, null: false
      t.string :active_job_id, index: { unique: true }
      t.datetime :scheduled_at
      t.datetime :finished_at, index: true
      t.string :concurrency_key
      
      t.timestamps

      t.index [ :class_name, :finished_at ], name: "index_solid_queue_jobs_for_filtering"
      t.index [ :scheduled_at, :finished_at ], name: "index_solid_queue_jobs_for_alerting"
    end

    create_table :solid_queue_scheduled_executions do |t|
      t.references :job, null: false, foreign_key: { to_table: :solid_queue_jobs }, index: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.datetime :scheduled_at, null: false

      t.timestamps

      t.index [ :scheduled_at, :priority, :job_id ], name: "index_solid_queue_dispatch_all"
    end

    create_table :solid_queue_ready_executions do |t|
      t.references :job, null: false, foreign_key: { to_table: :solid_queue_jobs }, index: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false

      t.timestamps

      t.index [ :priority, :job_id ], name: "index_solid_queue_poll_all"
      t.index [ :queue_name, :priority, :job_id ], name: "index_solid_queue_poll_by_queue"
    end

    create_table :solid_queue_claimed_executions do |t|
      t.references :job, null: false, foreign_key: { to_table: :solid_queue_jobs }, index: false
      t.bigint :process_id
      t.datetime :created_at, null: false

      t.index [ :process_id, :job_id ]
    end

    create_table :solid_queue_blocked_executions do |t|
      t.references :job, null: false, foreign_key: { to_table: :solid_queue_jobs }, index: false
      t.string :queue_name, null: false
      t.integer :priority, default: 0, null: false
      t.string :concurrency_key, null: false
      t.datetime :expires_at

      t.timestamps

      t.index [ :concurrency_key, :priority, :job_id ], name: "index_solid_queue_blocked_executions"
      t.index :expires_at
    end

    create_table :solid_queue_failed_executions do |t|
      t.references :job, null: false, foreign_key: { to_table: :solid_queue_jobs }, index: false
      t.text :error
      t.datetime :created_at, null: false

      t.index [ :job_id ], name: "index_solid_queue_failed_executions"
    end

    create_table :solid_queue_pauses do |t|
      t.string :queue_name, null: false, index: { unique: true }
      t.datetime :created_at, null: false
    end

    create_table :solid_queue_processes do |t|
      t.string :kind, null: false
      t.string :name
      t.datetime :last_heartbeat_at, null: false, index: true
      t.bigint :supervisor_id
      t.integer :pid, null: false
      t.string :hostname
      t.text :metadata

      t.timestamps
    end

    create_table :solid_queue_semaphores do |t|
      t.string :key, null: false, index: { unique: true }
      t.integer :value, default: 1, null: false
      t.datetime :expires_at, null: false, index: true

      t.timestamps

      t.check_constraint "value > 0", name: "chk_rails_solid_queue_semaphores_on_value"
    end
  end
end