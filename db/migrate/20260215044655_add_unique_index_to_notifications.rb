# frozen_string_literal: true

class AddUniqueIndexToNotifications < ActiveRecord::Migration[8.0]
  def up
    # 既存の重複データを除去（各グループで最新のレコードのみ保持）
    execute <<~SQL
      DELETE FROM notifications
      WHERE id NOT IN (
        SELECT MAX(id) FROM notifications
        GROUP BY account_id, from_account_id, activity_type, activity_id, notification_type
      )
    SQL

    # 重複通知を防止するユニークインデックス
    add_index :notifications,
              %i[account_id from_account_id activity_type activity_id notification_type],
              unique: true,
              name: 'index_notifications_uniqueness'
  end

  def down
    remove_index :notifications, name: 'index_notifications_uniqueness'
  end
end
