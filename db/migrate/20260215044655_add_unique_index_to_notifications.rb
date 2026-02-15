# frozen_string_literal: true

class AddUniqueIndexToNotifications < ActiveRecord::Migration[8.0]
  def change
    # 重複通知を防止するユニークインデックス
    add_index :notifications,
              %i[account_id from_account_id activity_type activity_id notification_type],
              unique: true,
              name: 'index_notifications_uniqueness'
  end
end
