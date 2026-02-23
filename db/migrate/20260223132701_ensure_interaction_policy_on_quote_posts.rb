# frozen_string_literal: true

class EnsureInteractionPolicyOnQuotePosts < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:quote_posts, :interaction_policy)

    add_column :quote_posts, :interaction_policy, :json
  end
end
