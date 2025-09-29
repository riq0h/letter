class AddAccessTokenIdToWebPushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:web_push_subscriptions, :access_token_id)
      add_column :web_push_subscriptions, :access_token_id, :integer
      add_index :web_push_subscriptions, :access_token_id
      add_foreign_key :web_push_subscriptions, :oauth_access_tokens, column: :access_token_id
    end
  end
end
