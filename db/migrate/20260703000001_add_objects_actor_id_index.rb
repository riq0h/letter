# frozen_string_literal: true

class AddObjectsActorIdIndex < ActiveRecord::Migration[8.0]
  def up
    # アカウントの投稿一覧（GET /api/v1/accounts/:id/statuses）用。
    # WHERE actor_id=? AND object_type IN ('Note','Question') [AND ...] ORDER BY id DESC LIMIT 20
    # は id 順で辿れるインデックスが無く、多作リモート（約2万投稿）で全投稿を
    # TEMP B-TREE ソートして12〜40秒かかっていた。
    # idx_objects_timeline は (actor_id, object_type, is_pinned_only, id) で is_pinned_only が
    # 中間にあり、is_pinned_only を絞らないこのクエリでは id 順スキャンにならない。
    # (actor_id, id) なら actor_id 固定で id 降順スキャン+LIMIT早期終了でソート不要。
    # ※かつて存在した idx_objects_actor_id_desc を実質的に復活させるもの。
    add_index :objects, %i[actor_id id], name: 'index_objects_on_actor_id_and_id', if_not_exists: true

    execute('ANALYZE objects')
  end

  def down
    remove_index :objects, name: 'index_objects_on_actor_id_and_id', if_exists: true
  end
end
