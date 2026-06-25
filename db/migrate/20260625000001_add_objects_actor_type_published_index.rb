# frozen_string_literal: true

class AddObjectsActorTypePublishedIndex < ActiveRecord::Migration[8.0]
  def up
    # アカウントの last_status_at 算出用。
    # AccountSerializer#preload_last_status_at の
    #   SELECT MAX(published_at) ... WHERE actor_id IN (...) AND object_type IN ('Note','Question') GROUP BY actor_id
    # が、既存の idx_objects_timeline (actor_id, object_type, is_pinned_only, id) では
    # published_at が末尾に無いため各アクターの全投稿（多作なリモートは2万件超）を走査し
    # ホームTL1リクエストで約450ms（最大の単一コスト）かかっていた。
    # (actor_id, object_type, published_at) なら各グループ末尾=MAXに直行でき数msになる。
    add_index :objects, %i[actor_id object_type published_at],
              name: 'idx_objects_actor_type_published', if_not_exists: true

    execute('ANALYZE objects')
  end

  def down
    remove_index :objects, name: 'idx_objects_actor_type_published', if_exists: true
  end
end
