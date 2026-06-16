# frozen_string_literal: true

class AddObjectsLocalCountsIndex < ActiveRecord::Migration[8.0]
  def up
    # nodeinfo/2.1 の統計COUNT用の被覆部分インデックス。
    # WHERE local=1 AND object_type='Note' を、20260611000001で追加した
    # idx_objects_object_type_created_at（object_type先頭）がプランナに誤選択され、
    # 41万件のNote行+テーブル参照で local=1 を確認して21秒かかっていた。
    # local subset（約6000行）のみの部分インデックスにし、object_typeと
    # in_reply_to_ap_idを含めることで以下2つのCOUNTがインデックスのみで完結する:
    #   - localPosts:    local=1 AND object_type='Note'
    #   - localComments: local=1 AND in_reply_to_ap_id IS NOT NULL
    # 本番データで検証済み: 21秒/3.6秒 → ともに数ms
    add_index :objects, %i[object_type in_reply_to_ap_id], where: 'local = 1',
                                                           name: 'idx_objects_local_counts', if_not_exists: true

    execute('ANALYZE objects')
  end

  def down
    remove_index :objects, name: 'idx_objects_local_counts', if_exists: true
  end
end
