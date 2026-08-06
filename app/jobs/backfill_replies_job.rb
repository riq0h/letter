# frozen_string_literal: true

# リモート投稿のスレッド(返信)をバックフィルするジョブ。
# 単一ユーザサーバには他人同士の返信が届かないため、スレッド表示を契機に
# FEP-7888のcontextコレクション(優先)またはActivityPub標準のrepliesコレクションを
# 辿って未知の返信を取得する。表示は次回のcontext取得時にローカルDBから反映される。
class BackfillRepliesJob < ApplicationJob
  queue_as :default

  MAX_ITEMS = 40   # 1回のバックフィルで解決する投稿数の上限
  MAX_PAGES = 3    # コレクションのページ追跡上限
  MAX_DEPTH = 2    # replies経由の再帰深さ(contextは全構成員を含むため再帰不要)
  QUICK_ITEMS = 8  # 同期クイックパスで解決する投稿数の上限

  # 同期クイックパス: スレッド表示のリクエスト内で、期限(deadline)まで返信を解決する。
  # コレクション取得1〜2回+未知アイテムの並列fetch(HTTPはGVLを解放するため並列が効く)、
  # SQLite書き込みは直列。取り切れなかった分は非同期のperformが完全化する
  def quick_pass(target, deadline:)
    raw = parse_raw(target)
    uris = quick_item_uris(raw)
    unknown = uris.reject { |u| ActivityPubObject.exists?(ap_id: u) }.first(QUICK_ITEMS)
    return 0 if unknown.empty?

    fetched = parallel_fetch(unknown, deadline: deadline)
    resolver = Search::RemoteResolverService.new
    created = 0
    fetched.each do |data|
      break if Time.current >= deadline

      # createは(未知アクターの解決を含み)DB書き込みを伴うため直列に行う
      created += 1 if resolver.send(:create_remote_object, data)
    end
    created
  end

  def perform(status_id)
    target = ActivityPubObject.find_by(id: status_id, local: false)
    return unless target

    @resolved = 0
    raw = parse_raw(target)

    if (context_url = usable_url(raw['context']))
      backfill_from_collection(context_url)
    elsif raw['replies'].present?
      backfill_replies_recursive(target, raw['replies'], depth: 1)
    end

    Rails.logger.info "🧵 Replies backfill for #{target.ap_id}: resolved #{@resolved} posts"
  end

  private

  def parse_raw(object)
    JSON.parse(object.raw_data || '{}')
  rescue JSON::ParserError
    {}
  end

  # クイックパス用: ページ追跡なしで最初のページからアイテムURIを集める
  def quick_item_uris(raw)
    collection = if (source = usable_url(raw['context']))
                   ActivityPubHttpClient.fetch_object(source, timeout: 4)
                 else
                   inline_or_fetch_replies(raw['replies'])
                 end
    return [] unless collection.is_a?(Hash)

    page = collection
    page = fetch_first_page(page) if page['items'].blank? && page['orderedItems'].blank?
    return [] unless page.is_a?(Hash)

    (page['orderedItems'] || page['items'] || []).filter_map do |item|
      uri = item.is_a?(String) ? item : item['id']
      uri if uri.is_a?(String) && uri.start_with?('http')
    end
  end

  def inline_or_fetch_replies(replies_value)
    if (url = usable_url(replies_value))
      ActivityPubHttpClient.fetch_object(url, timeout: 4)
    elsif replies_value.is_a?(Hash)
      replies_value
    end
  end

  # HTTPフェッチのみ並列化する。期限までに完了したものだけを返し、残りは打ち切る
  def parallel_fetch(uris, deadline:)
    threads = uris.map do |uri|
      Thread.new do
        Thread.current.report_on_exception = false
        ActivityPubHttpClient.fetch_object(uri, timeout: 4)
      end
    end

    threads.filter_map do |t|
      remaining = deadline - Time.current
      if remaining.positive? && t.join(remaining)
        t.value
      else
        t.kill
        nil
      end
    end
  rescue StandardError
    []
  end

  def usable_url(value)
    value.is_a?(String) && value.start_with?('http') ? value : nil
  end

  # コレクション(context)を辿って全構成員を解決する
  def backfill_from_collection(collection_url)
    each_collection_item(collection_url) do |item_uri|
      resolve_item(item_uri)
      break if budget_exhausted?
    end
  end

  # repliesコレクションを深さ制限付きで再帰的に辿る
  def backfill_replies_recursive(_parent, replies_value, depth:)
    return if depth > MAX_DEPTH || budget_exhausted?

    new_objects = []
    each_replies_item(replies_value) do |item_uri|
      obj = resolve_item(item_uri)
      new_objects << obj if obj
      break if budget_exhausted?
    end

    # 取得した返信の、さらに返信を辿る
    new_objects.each do |obj|
      raw = parse_raw(obj)
      backfill_replies_recursive(obj, raw['replies'], depth: depth + 1) if raw['replies'].present?
      break if budget_exhausted?
    end
  end

  # repliesは「URL文字列」または「firstページをインラインで含むHash」の両形式がある
  def each_replies_item(replies_value, &)
    if (url = usable_url(replies_value))
      each_collection_item(url, &)
    elsif replies_value.is_a?(Hash)
      first = replies_value['first']
      if (url = usable_url(first))
        each_collection_item(url, &)
      elsif first.is_a?(Hash)
        walk_pages(first, &)
      end
    end
  end

  # コレクションURLを取得し、items/orderedItemsとnextページを辿る
  def each_collection_item(url, &)
    page = ActivityPubHttpClient.fetch_object(url)
    return unless page

    # OrderedCollection本体ならfirstページへ
    page = fetch_first_page(page) if page['items'].blank? && page['orderedItems'].blank?
    walk_pages(page, &)
  end

  def fetch_first_page(collection)
    first = collection&.dig('first')
    return first if first.is_a?(Hash)
    return ActivityPubHttpClient.fetch_object(first) if usable_url(first)

    nil
  end

  def walk_pages(page)
    MAX_PAGES.times do
      break unless page.is_a?(Hash)

      items = page['orderedItems'] || page['items'] || []
      items.each do |item|
        uri = item.is_a?(String) ? item : item['id']
        yield(uri) if uri.present?
        break if budget_exhausted?
      end
      return if budget_exhausted?

      next_page = page['next']
      break if next_page.blank?

      page = next_page.is_a?(Hash) ? next_page : ActivityPubHttpClient.fetch_object(next_page)
    end
  end

  # 未知のURIだけをリモート解決する(既知ならスキップ)
  def resolve_item(uri)
    return nil unless uri.is_a?(String) && uri.start_with?('http')
    return nil if ActivityPubObject.exists?(ap_id: uri)

    obj = Search::RemoteResolverService.new.resolve_remote_status(uri)
    @resolved += 1 if obj
    obj
  rescue StandardError => e
    Rails.logger.debug { "Replies backfill skipped #{uri}: #{e.message}" }
    nil
  end

  def budget_exhausted?
    @resolved >= MAX_ITEMS
  end
end
