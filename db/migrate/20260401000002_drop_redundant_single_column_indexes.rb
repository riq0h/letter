# frozen_string_literal: true

class DropRedundantSingleColumnIndexes < ActiveRecord::Migration[8.0]
  def change
    # 複合インデックス idx_objects_actor_id_desc (actor_id, id DESC) が存在するため、
    # 単一カラムの actor_id インデックスは冗長。
    # 削除することでSQLiteのクエリプランナーが複合インデックスを選択し、
    # ORDER BY objects.id DESC の最適化が期待できる。
    remove_index :objects, name: 'index_objects_on_actor_id', if_exists: true
  end
end
