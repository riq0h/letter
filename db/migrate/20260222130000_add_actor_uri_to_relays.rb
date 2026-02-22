# frozen_string_literal: true

class AddActorUriToRelays < ActiveRecord::Migration[8.0]
  def change
    add_column :relays, :actor_uri, :string
  end
end
