# frozen_string_literal: true

class UserTimelineQuery
  def initialize(user)
    @user = user
  end

  def apply(query)
    query = exclude_blocked_users(query)
    query = exclude_muted_users(query)
    exclude_domain_blocked_users(query)
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
end
