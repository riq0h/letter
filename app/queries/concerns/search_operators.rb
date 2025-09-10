# frozen_string_literal: true

module SearchOperators
  private

  def search_operators?
    query.match?(/\b(from|to|has|is|before|after):/i)
  end

  def search_with_operators
    search_filters = parse_search_operators

    # from:me の場合は現在のユーザの投稿を検索
    return search_current_user_posts(search_filters[:remaining_query]) if search_filters[:from] == 'me' && current_user.present?

    # from:username の場合は指定ユーザの投稿を検索
    if search_filters[:from].present? && search_filters[:from] != 'me'
      return search_user_posts_by_username(search_filters[:from], search_filters[:remaining_query])
    end

    # その他の演算子（実装していない場合は通常検索にフォールバック）
    remaining_query = search_filters[:remaining_query]
    if remaining_query.present?
      # 元のクエリを残りのクエリに置き換えて通常検索
      old_query = @query
      @query = remaining_query
      result = search_full_text_only
      @query = old_query
      result
    else
      []
    end
  end

  def parse_search_operators
    filters = {}
    remaining_query = query.dup

    # from: 演算子
    if remaining_query =~ /\bfrom:(\w+)/i
      filters[:from] = ::Regexp.last_match(1)
      remaining_query.gsub!(/\bfrom:\w+\s*/i, '')
    end

    # to: 演算子
    if remaining_query =~ /\bto:(\w+)/i
      filters[:to] = ::Regexp.last_match(1)
      remaining_query.gsub!(/\bto:\w+\s*/i, '')
    end

    # has: 演算子
    if remaining_query =~ /\bhas:(\w+)/i
      filters[:has] = ::Regexp.last_match(1)
      remaining_query.gsub!(/\bhas:\w+\s*/i, '')
    end

    # is: 演算子
    if remaining_query =~ /\bis:(\w+)/i
      filters[:is] = ::Regexp.last_match(1)
      remaining_query.gsub!(/\bis:\w+\s*/i, '')
    end

    filters[:remaining_query] = remaining_query.strip
    filters
  end

  def search_current_user_posts(search_term = nil)
    return [] if current_user.blank?

    base_query = ActivityPubObject.where(actor_id: current_user.id)
                                  .where(object_type: 'Note')
                                  .where(visibility: %w[public unlisted private])

    if search_term.present?
      # 検索語がある場合はuser_posts_searchを使用
      search_query = SearchQuery.new(
        query: search_term,
        limit: limit,
        offset: offset
      )
      search_query.user_posts_search(current_user.id)
    else
      # 検索語がない場合は全ての投稿を返す
      base_query.includes(:actor)
                .order('objects.id DESC')
                .limit(limit)
                .offset(offset)
    end
  end

  def search_user_posts_by_username(username, search_term = nil)
    # ローカルユーザを検索
    actor = Actor.find_by(username: username, local: true)
    return [] if actor.blank?

    if search_term.present?
      search_query = SearchQuery.new(
        query: search_term,
        limit: limit,
        offset: offset
      )
      search_query.user_posts_search(actor.id)
    else
      # 検索語がない場合は公開投稿のみ返す
      ActivityPubObject.where(actor_id: actor.id)
                       .where(object_type: 'Note')
                       .where(visibility: %w[public unlisted])
                       .includes(:actor)
                       .order('objects.id DESC')
                       .limit(limit)
                       .offset(offset)
    end
  end
end
