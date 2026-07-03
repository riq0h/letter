# frozen_string_literal: true

class RebuildPostSearchFtsWithTrigram < ActiveRecord::Migration[8.0]
  # 日本語の部分一致検索を可能にする。
  # デフォルトの unicode61 トークナイザは日本語の連続文字列を1トークン化するため、
  # 「クラッチバッグ」の途中にある「バッグ」等が検索でヒットしない（実測で94%取りこぼし）。
  # trigram トークナイザ（3文字単位で索引）に置き換えると部分一致が可能になる。
  # post_search_fts は外部コンテンツFTS（content='post_search'）なので、
  # 作り直し後に 'rebuild' で既存の post_search から索引を再構築する。
  # 既存トリガー（post_search_ai/ad/au）は post_search_fts を名前参照するため変更不要。
  def up
    recreate_fts(tokenize: "tokenize='trigram'")
  end

  def down
    recreate_fts(tokenize: nil)
  end

  private

  def recreate_fts(tokenize:)
    tokenize_clause = tokenize ? ", #{tokenize}" : ''
    execute 'DROP TABLE IF EXISTS post_search_fts;'
    execute <<~SQL.squish
      CREATE VIRTUAL TABLE post_search_fts USING fts5(
        object_id UNINDEXED,
        content,
        content_plaintext,
        actor_username,
        content='post_search',
        content_rowid='rowid'#{tokenize_clause}
      );
    SQL
    # 既存の post_search から索引を再構築
    execute "INSERT INTO post_search_fts(post_search_fts) VALUES('rebuild');"
  end
end
