# frozen_string_literal: true

class AddTimelinePerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Home timeline: objects filtered by actor_id, ordered by id DESC
    add_index :objects, [:actor_id, :id], order: { id: :desc },
              name: 'idx_objects_actor_id_desc', if_not_exists: true

    # Reblog timeline: reblogs filtered by actor_id, ordered by created_at DESC
    add_index :reblogs, [:actor_id, :created_at], order: { created_at: :desc },
              name: 'idx_reblogs_actor_created_at_desc', if_not_exists: true

    # Notifications: filtered by account_id, ordered by id DESC
    add_index :notifications, [:account_id, :id], order: { id: :desc },
              name: 'idx_notifications_account_id_desc', if_not_exists: true
  end
end
