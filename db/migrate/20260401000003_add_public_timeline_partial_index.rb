# frozen_string_literal: true

class AddPublicTimelinePartialIndex < ActiveRecord::Migration[8.0]
  def change
    add_index :objects, [:id],
              order: { id: :desc },
              name: 'idx_objects_public_timeline',
              where: "visibility = 'public' AND object_type IN ('Note', 'Question') AND is_pinned_only = 0",
              if_not_exists: true
  end
end
