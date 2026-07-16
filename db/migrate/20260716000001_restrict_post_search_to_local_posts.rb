# frozen_string_literal: true

# 検索インデックス(post_search)をローカル投稿限定にする。
#
# 全検索経路(SearchQueryのFTS/LIKE/時間範囲)は actors.local = 1 で絞るのに、
# post_searchのトリガーは全公開Noteを索引しており、70.5万行中ローカルは6千行
# (99%が死重)だった。このためLIKEフォールバック(riq0h.jp等のドット入りクエリ)の
# フルスキャンがコールドで13秒に達していた。ローカル限定にすると数msになる。
class RestrictPostSearchToLocalPosts < ActiveRecord::Migration[8.0]
  def up
    # FTSミラートリガーを一旦落とす(70万行のDELETEで1行ずつFTS削除が走るのを防ぐ)
    drop_fts_mirror_triggers

    # リモート投稿の行を除去
    execute 'DELETE FROM post_search WHERE object_id IN (SELECT id FROM objects WHERE local = 0)'

    # objects→post_search トリガーをローカル限定で作り直す
    recreate_objects_triggers(local_only: true)

    # FTSをローカルのみで再構築(trigramは20260703000002と同一構成)
    recreate_fts_and_mirror_triggers

    execute 'ANALYZE post_search'
  end

  def down
    drop_fts_mirror_triggers

    # リモート公開Noteを索引に戻す
    execute <<~SQL.squish
      INSERT INTO post_search(object_id, content, content_plaintext, actor_username)
      SELECT o.id, o.content, o.content_plaintext, a.username
      FROM objects o JOIN actors a ON a.id = o.actor_id
      WHERE o.local = 0 AND o.object_type = 'Note' AND o.visibility = 'public'
        AND o.id NOT IN (SELECT object_id FROM post_search)
    SQL

    recreate_objects_triggers(local_only: false)
    recreate_fts_and_mirror_triggers
  end

  private

  def drop_fts_mirror_triggers
    %w[post_search_ai post_search_ad post_search_au].each { |t| execute "DROP TRIGGER IF EXISTS #{t}" }
  end

  def recreate_objects_triggers(local_only:)
    local_clause = local_only ? ' AND NEW.local = 1' : ''
    execute 'DROP TRIGGER IF EXISTS objects_search_insert'
    execute 'DROP TRIGGER IF EXISTS objects_search_update'

    execute <<~SQL.squish
      CREATE TRIGGER objects_search_insert AFTER INSERT ON objects
      WHEN NEW.object_type = 'Note' AND NEW.visibility = 'public'#{local_clause}
      BEGIN
        INSERT INTO post_search(object_id, content, content_plaintext, actor_username)
        SELECT NEW.id, NEW.content, NEW.content_plaintext, actors.username
        FROM actors WHERE actors.id = NEW.actor_id;
      END
    SQL

    execute <<~SQL.squish
      CREATE TRIGGER objects_search_update AFTER UPDATE ON objects
      WHEN NEW.object_type = 'Note' AND NEW.visibility = 'public'#{local_clause}
      BEGIN
        DELETE FROM post_search WHERE object_id = OLD.id;
        INSERT INTO post_search(object_id, content, content_plaintext, actor_username)
        SELECT NEW.id, NEW.content, NEW.content_plaintext, actors.username
        FROM actors WHERE actors.id = NEW.actor_id;
      END
    SQL
    # objects_search_delete は変更不要(post_searchに行が無ければ何もしないため)
  end

  def recreate_fts_and_mirror_triggers
    execute 'DROP TABLE IF EXISTS post_search_fts'
    execute <<~SQL.squish
      CREATE VIRTUAL TABLE post_search_fts USING fts5(
        object_id UNINDEXED,
        content,
        content_plaintext,
        actor_username,
        content='post_search',
        content_rowid='rowid', tokenize='trigram'
      )
    SQL

    create_fts_mirror_triggers
    execute "INSERT INTO post_search_fts(post_search_fts) VALUES('rebuild')"
  end

  def create_fts_mirror_triggers
    execute <<~SQL.squish
      CREATE TRIGGER post_search_ai AFTER INSERT ON post_search BEGIN
        INSERT INTO post_search_fts(rowid, object_id, content, content_plaintext, actor_username)
        VALUES (new.rowid, new.object_id, new.content, new.content_plaintext, new.actor_username);
      END
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER post_search_ad AFTER DELETE ON post_search BEGIN
        INSERT INTO post_search_fts(post_search_fts, rowid, object_id, content, content_plaintext, actor_username)
        VALUES('delete', old.rowid, old.object_id, old.content, old.content_plaintext, old.actor_username);
      END
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER post_search_au AFTER UPDATE ON post_search BEGIN
        INSERT INTO post_search_fts(post_search_fts, rowid, object_id, content, content_plaintext, actor_username)
        VALUES('delete', old.rowid, old.object_id, old.content, old.content_plaintext, old.actor_username);
        INSERT INTO post_search_fts(rowid, object_id, content, content_plaintext, actor_username)
        VALUES (new.rowid, new.object_id, new.content, new.content_plaintext, new.actor_username);
      END
    SQL
  end
end
