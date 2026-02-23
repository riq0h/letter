# frozen_string_literal: true

class EnsureInteractionPolicyOnQuotePosts < ActiveRecord::Migration[8.0]
  def change
    unless table_exists?(:quote_authorizations)
      create_table :quote_authorizations do |t|
        t.string :ap_id
        t.references :actor, null: false, foreign_key: true
        t.references :quote_post, null: false, foreign_key: true
        t.string :interacting_object_id
        t.string :interaction_target_id

        t.timestamps
      end

      add_index :quote_authorizations, :ap_id, unique: true
      add_index :quote_authorizations, :interacting_object_id
      add_index :quote_authorizations, :interaction_target_id
    end

    return if column_exists?(:quote_posts, :interaction_policy)

    add_column :quote_posts, :interaction_policy, :json
  end
end
