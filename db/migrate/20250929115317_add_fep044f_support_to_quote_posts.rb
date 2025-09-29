class AddFep044fSupportToQuotePosts < ActiveRecord::Migration[8.0]
  def change
    add_column :quote_posts, :quote_authorization_url, :string
    add_column :quote_posts, :interaction_policy, :json

    add_index :quote_posts, :quote_authorization_url
  end
end
