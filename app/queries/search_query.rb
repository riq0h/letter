# frozen_string_literal: true

class SearchQuery
  attr_accessor :query, :since_time, :until_time, :limit, :offset

  def initialize(attributes = {})
    @query = attributes[:query]
    @since_time = attributes[:since_time]
    @until_time = attributes[:until_time]
    @limit = attributes[:limit] || 30
    @offset = attributes[:offset] || 0
  end

  def search
    return [] if query.blank?

    if since_time.present? || until_time.present?
      search_with_time_range
    else
      search_full_text_only
    end
  end

  def timeline(max_id: nil, min_id: nil)
    base_query = ActivityPubObject.joins(:actor)
                                  .where(object_type: 'Note')
                                  .where(local: true)
                                  .where(visibility: 'public')

    base_query = base_query.where(objects: { id: ...max_id }) if max_id.present?
    base_query = base_query.where('objects.id > ?', min_id) if min_id.present?
    base_query.order('objects.id DESC').limit(limit)
  end

  def user_posts(actor_id, max_id: nil)
    base_query = ActivityPubObject.where(actor_id: actor_id)
                                  .where(object_type: 'Note')
                                  .where(visibility: %w[public unlisted])

    base_query = base_query.where(objects: { id: ...max_id }) if max_id.present?
    base_query.order('objects.id DESC').limit(limit)
  end

  def posts_in_time_range(start_time, end_time)
    start_id = time_to_snowflake_id(start_time)
    end_id = time_to_snowflake_id(end_time)

    ActivityPubObject.where('objects.id BETWEEN ? AND ?', start_id, end_id)
                     .where(object_type: 'Note')
                     .where(local: true)
                     .order('objects.id DESC')
                     .limit(limit)
  end

  def user_posts_search(target_actor_id)
    return [] if query.blank?

    object_ids = matching_object_ids
    return [] if object_ids.empty?

    ActivityPubObject.where(id: object_ids)
                     .where(actor_id: target_actor_id)
                     .where(object_type: 'Note')
                     .where(visibility: %w[public unlisted])
                     .includes(:actor)
                     .order('objects.id DESC')
  end

  private

  def search_with_time_range
    object_ids = matching_object_ids_with_time_range
    return [] if object_ids.empty?

    ActivityPubObject.where(id: object_ids)
                     .includes(:actor)
                     .order('objects.id DESC')
  end

  def search_full_text_only
    if contains_special_characters?
      try_like_search
    else
      execute_fts5_search
    end
  end

  def build_fts5_query
    if query.include?(' ')
      keywords = query.split(/\s+/).map { |word| "\"#{word}\"" }
      keywords.join(' AND ')
    else
      "\"#{query}\""
    end
  end

  def execute_fts5_search
    object_ids = matching_object_ids
    return [] if object_ids.empty?

    ActivityPubObject.where(id: object_ids)
                     .includes(:actor)
                     .order('objects.id DESC')
  end

  def matching_object_ids
    fts_results = try_fts5_search
    return fts_results if fts_results.any?

    try_like_search
  end

  def matching_object_ids_with_time_range
    return [] unless fts5_table?

    since_id = since_time.present? ? time_to_snowflake_id(since_time) : nil
    until_id = until_time.present? ? time_to_snowflake_id(until_time) : nil
    fts_query = build_japanese_friendly_fts_query

    sql = build_time_range_sql(since_id, until_id)
    params = build_time_range_params(sql, fts_query, since_id, until_id)

    results = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql(params)
    )

    results.pluck('object_id')
  end

  def build_time_range_sql(since_id, until_id)
    base_sql = <<~SQL.squish
      SELECT fts.object_id
      FROM post_search_fts fts
      INNER JOIN objects o ON fts.object_id = o.id
      INNER JOIN actors a ON o.actor_id = a.id
      WHERE fts.content_plaintext MATCH ?
    SQL

    if since_id && until_id
      "#{base_sql} AND fts.object_id BETWEEN ? AND ? AND a.local = 1 ORDER BY fts.object_id DESC LIMIT ? OFFSET ?"
    elsif since_id
      "#{base_sql} AND fts.object_id >= ? AND a.local = 1 ORDER BY fts.object_id DESC LIMIT ? OFFSET ?"
    elsif until_id
      "#{base_sql} AND fts.object_id <= ? AND a.local = 1 ORDER BY fts.object_id DESC LIMIT ? OFFSET ?"
    else
      "#{base_sql} AND a.local = 1 ORDER BY fts.object_id DESC LIMIT ? OFFSET ?"
    end
  end

  def build_time_range_params(sql, fts_query, since_id, until_id)
    if since_id && until_id
      [sql, fts_query, since_id, until_id, limit, offset]
    elsif since_id
      [sql, fts_query, since_id, limit, offset]
    elsif until_id
      [sql, fts_query, until_id, limit, offset]
    else
      [sql, fts_query, limit, offset]
    end
  end

  def try_fts5_search
    return [] unless fts5_table?

    fts_query = build_japanese_friendly_fts_query

    sql = <<~SQL.squish
      SELECT fts.object_id
      FROM post_search_fts fts
      INNER JOIN objects o ON fts.object_id = o.id
      INNER JOIN actors a ON o.actor_id = a.id
      WHERE fts.content_plaintext MATCH ?
        AND a.local = 1
      ORDER BY fts.object_id DESC
      LIMIT ? OFFSET ?
    SQL

    results = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([sql, fts_query, limit, offset])
    )

    results.pluck('object_id')
  rescue SQLite3::SQLException => e
    Rails.logger.warn "FTS5 search failed: #{e.message}"
    []
  end

  def try_like_search
    sql = <<~SQL.squish
      SELECT lps.object_id
      FROM post_search lps
      INNER JOIN objects o ON lps.object_id = o.id
      INNER JOIN actors a ON o.actor_id = a.id
      WHERE lps.content_plaintext LIKE ?
        AND a.local = 1
      ORDER BY lps.object_id DESC
      LIMIT ? OFFSET ?
    SQL

    like_query = "%#{query}%"
    results = ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql([sql, like_query, limit, offset])
    )

    results.pluck('object_id')
  rescue SQLite3::SQLException => e
    Rails.logger.warn "Like search failed: #{e.message}"
    []
  end

  def build_japanese_friendly_fts_query
    if contains_japanese_characters?
      build_japanese_query
    elsif query.include?(' ')
      build_english_multi_word_query
    else
      build_single_word_query
    end
  end

  def contains_japanese_characters?
    query.match?(/[\p{Hiragana}\p{Katakana}\p{Han}]/)
  end

  def contains_special_characters?
    special_chars = ['@', '"', '^', '*', '(', ')', '[', ']', '{', '}', '\\', '.']
    special_chars.any? { |char| query.include?(char) }
  end

  def build_japanese_query
    keywords = query.split(/\s+/).compact_blank
    if keywords.length > 1
      keywords.map do |word|
        if word.length >= 2
          "#{word}*"
        else
          "\"#{word}\""
        end
      end.join(' OR ')
    else
      build_single_word_query
    end
  end

  def build_english_multi_word_query
    keywords = query.split(/\s+/).map { |word| "\"#{word}\"" }
    keywords.join(' AND ')
  end

  def build_single_word_query
    if query.length >= 2
      "#{query}*"
    else
      "\"#{query}\""
    end
  end

  def fts5_table?
    result = ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='post_search_fts'"
    )
    result.any?
  rescue StandardError
    false
  end

  def time_to_snowflake_id(time)
    Letter::Snowflake.generate_at(time, sequence: 0)
  end

  def snowflake_id_to_time(snowflake_id)
    Letter::Snowflake.extract_timestamp(snowflake_id)
  rescue StandardError
    nil
  end
end
