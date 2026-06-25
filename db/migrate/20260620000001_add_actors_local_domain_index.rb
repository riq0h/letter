# frozen_string_literal: true

class AddActorsLocalDomainIndex < ActiveRecord::Migration[8.0]
  def up
    # distinct domain集計用の被覆複合インデックス。
    # /api/v1/instance の domain_count = Actor.where(local:false).distinct.count(:domain)
    # が index_actors_on_local で10万件超のリモートactorを引き、domainをテーブル参照して
    # TEMP B-TREEで重複排除するため14.9秒かかっていた（リモートactorは増加中）。
    # (local, domain) でlocal=0のdomainがインデックスのみ・整列済みで読めるようになり、
    # domain_count / peers / emoji_discovery の distinct domain 系がすべて高速化する。
    # 本番データで検証済み: 14.9秒 → 4ms
    add_index :actors, %i[local domain], name: 'idx_actors_local_domain', if_not_exists: true

    execute('ANALYZE actors')
  end

  def down
    remove_index :actors, name: 'idx_actors_local_domain', if_exists: true
  end
end
