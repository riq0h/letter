# frozen_string_literal: true

class DropRedundantSingleColumnIndexes < ActiveRecord::Migration[8.0]
  def change
    # is_pinned_only インデックスを削除
    # 99%以上の行が false で選択性が極めて低く、
    # クエリプランナーがこのインデックスを誤選択する原因となっている。
    remove_index :objects, name: 'index_objects_on_is_pinned_only', if_exists: true

    # actor_id 単一カラムインデックスを削除
    # 複合インデックス idx_objects_actor_id_desc (actor_id, id DESC) がカバーするため冗長。
    # 単一カラム版が存在するとプランナーが複合インデックスより優先してしまう。
    remove_index :objects, name: 'index_objects_on_actor_id', if_exists: true
  end
end
