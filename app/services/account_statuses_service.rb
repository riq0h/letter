# frozen_string_literal: true

class AccountStatusesService
  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def call
    return pinned_statuses_only if pinned_only?

    regular_statuses_with_optional_pinned
  end

  private

  attr_reader :account, :params

  def pinned_only?
    params[:pinned] == 'true'
  end

  def first_page?
    params[:max_id].blank? && params[:since_id].blank? && params[:min_id].blank?
  end

  def limit
    params[:limit] || 20
  end

  def pinned_statuses_only
    AccountStatusesQuery.new(account)
                        .pinned_only
                        .limit(limit)
                        .map(&:object)
  end

  def regular_statuses_with_optional_pinned
    regular_statuses = build_regular_statuses_query

    return regular_statuses.call.to_a unless first_page?

    pinned_objects = fetch_pinned_objects
    regular_without_pinned = regular_statuses.exclude_pinned(pinned_objects.map(&:id))
                                             .call

    (pinned_objects + regular_without_pinned.to_a).first(limit)
  end

  def build_regular_statuses_query
    query = AccountStatusesQuery.new(account)

    query = query.exclude_replies if params[:exclude_replies] == 'true'
    query = query.only_media if params[:only_media] == 'true'

    query.paginate(
      max_id: params[:max_id],
      since_id: params[:since_id],
      min_id: params[:min_id]
    )
         .with_includes
         .ordered
         .limit(limit)
  end

  def fetch_pinned_objects
    AccountStatusesQuery.new(account)
                        .pinned_only
                        .map(&:object)
  end
end
