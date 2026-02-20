class AddDisplayNameToTags < ActiveRecord::Migration[8.0]
  def change
    add_column :tags, :display_name, :string
  end
end
