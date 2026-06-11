# frozen_string_literal: true

class AddObjectsPublicTimelineIndex < ActiveRecord::Migration[8.0]
  def up
    # 連合タイムライン（公開TL）用の部分インデックス。
    # 本番のSQLiteプランナは複合インデックス+60万行のTEMP B-TREEソート
    # （実測2〜5.5秒）を選ぶため、id降順の部分インデックスを用意して
    # TimelineQuery側でINDEXED BY指定する（早期終了で数十行の走査になる）
    add_index :objects, :id, order: { id: :desc },
                             where: "visibility = 'public' AND is_pinned_only = 0",
                             name: 'idx_objects_public_id_desc', if_not_exists: true

    execute('ANALYZE objects')
  end

  def down
    remove_index :objects, name: 'idx_objects_public_id_desc', if_exists: true
  end
end
