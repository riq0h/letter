# frozen_string_literal: true

class AddCoveringIndexForTimeline < ActiveRecord::Migration[8.0]
  def up
    # objectsのカバリングインデックス追加（タイムラインクエリ最適化）
    # (actor_id, id DESC) → (actor_id, object_type, is_pinned_only, id DESC)
    # 検索・フィルタ・ソートがすべてインデックスのみで完結する
    remove_index :objects, name: 'idx_objects_actor_id_desc', if_exists: true
    add_index :objects, [:actor_id, :object_type, :is_pinned_only, :id],
              order: { id: :desc },
              name: 'idx_objects_timeline',
              if_not_exists: true

    # 複合インデックスでカバーされる冗長な単一カラムインデックスを削除
    # テスト環境で削除後に複合インデックスへのフォールバックを確認済み
    remove_index :objects, name: 'index_objects_on_object_type', if_exists: true
    remove_index :objects, name: 'index_objects_on_edited_at', if_exists: true
    remove_index :reblogs, name: 'index_reblogs_on_actor_id', if_exists: true
    remove_index :favourites, name: 'index_favourites_on_actor_id', if_exists: true
    remove_index :blocks, name: 'index_blocks_on_actor_id', if_exists: true
    remove_index :bookmarks, name: 'index_bookmarks_on_actor_id', if_exists: true
    remove_index :mutes, name: 'index_mutes_on_actor_id', if_exists: true
    remove_index :follows, name: 'index_follows_on_actor_id', if_exists: true
    remove_index :mentions, name: 'index_mentions_on_object_id', if_exists: true
    remove_index :object_tags, name: 'index_object_tags_on_object_id', if_exists: true
    remove_index :custom_emojis, name: 'index_custom_emojis_on_shortcode', if_exists: true
    remove_index :notifications, name: 'index_notifications_on_account_id', if_exists: true
    remove_index :pinned_statuses, name: 'index_pinned_statuses_on_actor_id', if_exists: true
    remove_index :poll_votes, name: 'index_poll_votes_on_poll_id', if_exists: true
    remove_index :status_edits, name: 'index_status_edits_on_object_id', if_exists: true
    remove_index :account_notes, name: 'index_account_notes_on_actor_id', if_exists: true
    remove_index :domain_blocks, name: 'index_domain_blocks_on_actor_id', if_exists: true
    remove_index :followed_tags, name: 'index_followed_tags_on_actor_id', if_exists: true
    remove_index :markers, name: 'index_markers_on_actor_id', if_exists: true
    remove_index :tag_usage_histories, name: 'index_tag_usage_histories_on_tag_id', if_exists: true
    remove_index :user_limits, name: 'index_user_limits_on_actor_id', if_exists: true
  end

  def down
    remove_index :objects, name: 'idx_objects_timeline', if_exists: true
    add_index :objects, [:actor_id, :id], order: { id: :desc },
              name: 'idx_objects_actor_id_desc', if_not_exists: true
    add_index :objects, :object_type, name: 'index_objects_on_object_type', if_not_exists: true
    add_index :objects, :edited_at, name: 'index_objects_on_edited_at', if_not_exists: true
    add_index :reblogs, :actor_id, name: 'index_reblogs_on_actor_id', if_not_exists: true
    add_index :favourites, :actor_id, name: 'index_favourites_on_actor_id', if_not_exists: true
    add_index :blocks, :actor_id, name: 'index_blocks_on_actor_id', if_not_exists: true
    add_index :bookmarks, :actor_id, name: 'index_bookmarks_on_actor_id', if_not_exists: true
    add_index :mutes, :actor_id, name: 'index_mutes_on_actor_id', if_not_exists: true
    add_index :follows, :actor_id, name: 'index_follows_on_actor_id', if_not_exists: true
    add_index :mentions, :object_id, name: 'index_mentions_on_object_id', if_not_exists: true
    add_index :object_tags, :object_id, name: 'index_object_tags_on_object_id', if_not_exists: true
    add_index :custom_emojis, :shortcode, name: 'index_custom_emojis_on_shortcode', if_not_exists: true
    add_index :notifications, :account_id, name: 'index_notifications_on_account_id', if_not_exists: true
    add_index :pinned_statuses, :actor_id, name: 'index_pinned_statuses_on_actor_id', if_not_exists: true
    add_index :poll_votes, :poll_id, name: 'index_poll_votes_on_poll_id', if_not_exists: true
    add_index :status_edits, :object_id, name: 'index_status_edits_on_object_id', if_not_exists: true
    add_index :account_notes, :actor_id, name: 'index_account_notes_on_actor_id', if_not_exists: true
    add_index :domain_blocks, :actor_id, name: 'index_domain_blocks_on_actor_id', if_not_exists: true
    add_index :followed_tags, :actor_id, name: 'index_followed_tags_on_actor_id', if_not_exists: true
    add_index :markers, :actor_id, name: 'index_markers_on_actor_id', if_not_exists: true
    add_index :tag_usage_histories, :tag_id, name: 'index_tag_usage_histories_on_tag_id', if_not_exists: true
    add_index :user_limits, :actor_id, name: 'index_user_limits_on_actor_id', if_not_exists: true
  end
end
