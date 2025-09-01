# frozen_string_literal: true

class UserTimelineQuery
  def initialize(user)
    @user = user
  end

  def apply(query)
    query = exclude_blocked_users(query)
    query = exclude_muted_users(query)
    query = exclude_domain_blocked_users(query)
    query = exclude_direct_messages(query)
    exclude_unwanted_replies(query)
  end

  private

  attr_reader :user

  def exclude_blocked_users(query)
    blocked_actor_ids = user.blocked_actors.pluck(:id)
    return query unless blocked_actor_ids.any?

    query.where.not(actors: { id: blocked_actor_ids })
  end

  def exclude_muted_users(query)
    muted_actor_ids = user.muted_actors.pluck(:id)
    return query unless muted_actor_ids.any?

    query.where.not(actors: { id: muted_actor_ids })
  end

  def exclude_domain_blocked_users(query)
    blocked_domains = user.domain_blocks.pluck(:domain)
    return query unless blocked_domains.any?

    query.where(
      'actors.domain IS NULL OR actors.domain NOT IN (?)',
      blocked_domains
    )
  end

  def exclude_direct_messages(query)
    # DMは表示しない
    query.where.not(visibility: 'direct')
  end

  def exclude_unwanted_replies(query)
    followed_actor_ids = user.followed_actors.pluck(:id) + [user.id]

    # リプライではない投稿は全て表示
    # リプライの場合は、以下の条件で表示：
    # 1. 自分宛のメンション
    # 2. 相互フォロー関係にあるユーザ間のリプライ
    query.where(
      '(objects.in_reply_to_ap_id IS NULL) OR ' \
      '(objects.id IN (SELECT object_id FROM mentions WHERE actor_id = ?)) OR ' \
      '(EXISTS (' \
      'SELECT 1 FROM objects reply_objects ' \
      'INNER JOIN actors reply_actors ON reply_objects.actor_id = reply_actors.id ' \
      'WHERE reply_objects.ap_id = objects.in_reply_to_ap_id ' \
      'AND reply_actors.id IN (?)' \
      '))',
      user.id,
      followed_actor_ids
    )
  end
end
