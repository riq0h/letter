# frozen_string_literal: true

class AddObjectsStatsAndLocalIndexes < ActiveRecord::Migration[8.0]
  def up
    # instance/activity の週次COUNT用カバリングインデックス
    # (object_type, created_at) でCOUNTがインデックスのみで完結し、
    # 2.3GBのテーブルフルスキャン×12回（60〜70秒）を数msに短縮する
    add_index :objects, %i[object_type created_at],
              name: 'idx_objects_object_type_created_at', if_not_exists: true

    # ローカルタイムライン用の部分インデックス（ローカル投稿は全体の1%未満のため、
    # 通常のインデックスではなく部分インデックスでサイズと走査範囲を最小化する）
    # API: /api/v1/timelines/public?local=true（ORDER BY id DESC）
    add_index :objects, :id, order: { id: :desc }, where: 'local = 1',
                             name: 'idx_objects_local_id_desc', if_not_exists: true

    # フロントエンド（トップページ・プロフィール）: ORDER BY published_at DESC, id DESC
    add_index :objects, %i[published_at id], where: 'local = 1',
                                             name: 'idx_objects_local_published_at', if_not_exists: true

    # 統計が古いとプランナが新インデックスを選ばない（本番データで検証済み:
    # ANALYZE前は4.3秒のTEMP B-TREEソート、ANALYZE後は5ms）
    execute('ANALYZE objects')
  end

  def down
    remove_index :objects, name: 'idx_objects_object_type_created_at', if_exists: true
    remove_index :objects, name: 'idx_objects_local_id_desc', if_exists: true
    remove_index :objects, name: 'idx_objects_local_published_at', if_exists: true
  end
end
