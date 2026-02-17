# frozen_string_literal: true

module ApiPagination
  extend ActiveSupport::Concern

  DEFAULT_LIMIT = 20
  MAX_LIMIT = 80

  private

  def insert_pagination_headers
    set_pagination_headers if @paginated_items.present?
  end

  def set_pagination_headers(items = @paginated_items)
    response.headers['Link'] = pagination_links(items)
    response.headers['X-Total-Count'] = total_count(items).to_s if include_total_count?
  end

  def pagination_links(items)
    links = []

    # 実際のレコードを取得（配列とActiveRecord relationの両方を処理）
    records = items.respond_to?(:to_a) ? items.to_a : items

    return '' if records.empty?

    # レコードからIDを抽出
    ids = extract_ids(records)

    # ページネーションリンクを構築
    links << link_next(ids) if ids.size >= limit_param
    links << link_prev(ids) if ids.any?

    links.compact.join(', ')
  end

  def extract_ids(records)
    records.filter_map do |record|
      case record
      when ActivityPubObject
        record.id
      when Reblog
        # リブログの場合はSnowflake互換のtimeline_idを使用
        record.timeline_id
      when Hash
        # objectキーを持つハッシュのタイムラインアイテムを処理
        if record[:object].is_a?(ActivityPubObject)
          record[:object].id
        elsif record[:object].is_a?(Reblog)
          record[:object].timeline_id
        end
      else
        record.id if record.respond_to?(:id)
      end
    end
  end

  def link_next(ids)
    return unless ids.any?

    # 現在ページの最後のIDが次ページのmax_idになる
    max_id = ids.last
    "<#{api_pagination_url(max_id: max_id)}>; rel=\"next\""
  end

  def link_prev(ids)
    return unless ids.any?

    # 現在ページの最初のIDが前ページのsince_idになる
    since_id = ids.first
    "<#{api_pagination_url(since_id: since_id)}>; rel=\"prev\""
  end

  def api_pagination_url(params_hash)
    url_params = request.query_parameters.merge(params_hash)

    # 競合するパラメータを削除
    if params_hash[:max_id]
      url_params.delete(:since_id)
      url_params.delete(:min_id)
    elsif params_hash[:since_id]
      url_params.delete(:max_id)
      url_params.delete(:min_id)
    end

    # limitが含まれることを保証
    url_params[:limit] = limit_param

    # URL構築
    "#{request.base_url}#{request.path}?#{url_params.to_query}"
  end

  def apply_collection_pagination(collection, table_name)
    collection = collection.where(id: ...(params[:max_id])) if params[:max_id].present?
    collection = collection.where("#{table_name}.id > ?", params[:since_id]) if params[:since_id].present?
    collection = collection.where("#{table_name}.id > ?", params[:min_id]) if params[:min_id].present?
    collection
  end

  def limit_param
    return DEFAULT_LIMIT if params[:limit].blank?

    params[:limit].to_i.clamp(1, MAX_LIMIT)
  end

  def include_total_count?
    # オプション: 一部のエンドポイントで総数ヘッダーを追加
    false
  end

  def total_count(items)
    return items.count if items.respond_to?(:count)

    items.size
  end

  # ページネーションとヘッダー設定を一度に行うヘルパーメソッド
  def paginate_with_headers(items)
    @paginated_items = items
    insert_pagination_headers
    items
  end
end
