# frozen_string_literal: true

module Search
  class SearchService
    def initialize(params, current_user)
      @params = params
      @current_user = current_user
      @remote_resolver = RemoteResolverService.new
    end

    def perform_search
      {
        accounts: search_accounts,
        statuses: search_statuses,
        hashtags: search_hashtags
      }
    end

    private

    attr_reader :params, :current_user, :remote_resolver

    def search_accounts
      return [] if search_query.blank?

      accounts = []
      accounts.concat(resolve_remote_accounts) if should_resolve_remote_accounts?
      accounts.concat(search_domain_accounts) if should_search_domain_accounts?
      accounts.concat(search_accounts_by_username) if should_search_local_accounts?
      accounts.uniq(&:id)
    end

    def search_statuses
      return [] if search_query.blank?
      return [] if account_query? || domain_query?

      statuses = []
      statuses.concat(resolve_remote_statuses) if should_resolve_remote_statuses?
      statuses.concat(search_local_statuses) if should_search_local_statuses?
      statuses.uniq(&:id)
    end

    def search_hashtags
      return [] if search_query.blank?
      return [] if %w[accounts statuses].include?(search_type)

      tag_query = search_query.gsub(/^#/, '')
      Tag.where('name LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(tag_query)}%")
         .order(usage_count: :desc)
         .limit(hashtag_limit)
    end

    def resolve_remote_accounts
      return [] if search_query.blank?
      return [] unless resolve_remote? && account_query?

      remote_account = remote_resolver.resolve_remote_account(search_query)
      remote_account ? [remote_account] : []
    end

    def search_domain_accounts
      return [] if search_query.blank?
      return [] unless domain_query?

      remote_resolver.search_domain_accounts(search_query)
    end

    def resolve_remote_statuses
      return [] if search_query.blank?
      return [] unless resolve_remote? && url_query?

      remote_status = remote_resolver.resolve_remote_status(search_query)
      remote_status ? [remote_status] : []
    end

    def search_accounts_by_username
      return [] if search_query.blank?
      return [] unless should_search_local_accounts?

      results = []

      # @username単体での完全一致検索
      if local_username_query?
        username = search_query.gsub(/^@/, '')
        exact_matches = Actor.where(username: username)
        results.concat(exact_matches)
      end

      # ローカルアカウントの部分一致検索
      sanitized_query = ActiveRecord::Base.sanitize_sql_like(clean_search_query)
      partial_matches = Actor.where(local: true)
                             .where('username LIKE ? OR display_name LIKE ?',
                                    "%#{sanitized_query}%", "%#{sanitized_query}%")
                             .limit(account_limit)

      results.concat(partial_matches)
      results.uniq(&:id).take(account_limit)
    end

    def search_local_statuses
      return [] if search_query.blank?
      return [] unless should_search_local_statuses?

      search_service = OptimizedSearchService.new(
        query: search_query,
        since_time: parse_time(params[:since]),
        until_time: parse_time(params[:until]),
        limit: status_limit,
        offset: params[:offset].to_i
      )

      results = search_service.search
      return [] if results.empty?

      # 文字列IDが返された場合はActivityPubObjectに変換
      if results.first.is_a?(String)
        ActivityPubObject.where(id: results).includes(:actor).order('objects.id DESC')
      else
        results
      end
    end

    def should_resolve_remote_accounts?
      resolve_remote? && account_query?
    end

    def should_resolve_remote_statuses?
      resolve_remote? && url_query?
    end

    def should_search_local_accounts?
      %w[statuses hashtags].exclude?(search_type)
    end

    def should_search_local_statuses?
      %w[accounts hashtags].exclude?(search_type)
    end

    def search_query
      params[:q].to_s.strip
    end

    def search_type
      params[:type]&.to_s
    end

    def resolve_remote?
      params[:resolve] == 'true' && current_user
    end

    def account_query?
      AccountIdentifierParser.account_query?(search_query)
    end

    def domain_query?
      AccountIdentifierParser.domain_query?(search_query)
    end

    def should_search_domain_accounts?
      domain_query?
    end

    def url_query?
      search_query.match?(/^https?:\/\//)
    end

    def local_username_query?
      search_query.start_with?('@') && search_query.count('@') == 1
    end

    def clean_search_query
      search_query.gsub(/^@/, '')
    end

    def account_limit
      return 0 if %w[statuses hashtags].include?(search_type)

      [params[:limit].to_i, 40].min.positive? ? [params[:limit].to_i, 40].min : 20
    end

    def status_limit
      return 0 if %w[accounts hashtags].include?(search_type)

      [params[:limit].to_i, 40].min.positive? ? [params[:limit].to_i, 40].min : 20
    end

    def hashtag_limit
      return 0 if %w[accounts statuses].include?(search_type)

      [params[:limit].to_i, 40].min.positive? ? [params[:limit].to_i, 40].min : 20
    end

    def parse_time(time_param)
      return nil if time_param.blank?

      Time.zone.parse(time_param)
    rescue ArgumentError
      nil
    end
  end
end
