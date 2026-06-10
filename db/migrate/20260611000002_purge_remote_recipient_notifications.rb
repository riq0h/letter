# frozen_string_literal: true

class PurgeRemoteRecipientNotifications < ActiveRecord::Migration[8.0]
  # リモートアクター宛の通知はどのクライアントからも読まれることがない
  # （通知APIはローカルユーザのみ認証可能）。NotificationCreation側の
  # ガード追加に合わせて、蓄積済みの不要データを削除する
  def up
    execute(<<~SQL.squish)
      DELETE FROM notifications
      WHERE account_id IN (SELECT id FROM actors WHERE local = 0)
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
