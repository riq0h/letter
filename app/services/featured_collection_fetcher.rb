# frozen_string_literal: true

class FeaturedCollectionFetcher
  def initialize
    @resolver = Search::RemoteResolverService.new
  end

  def fetch_for_actor(actor)
    return [] if actor.featured_url.blank?

    # 既存のPinnedStatusがある場合は、それらのオブジェクトを返す
    existing_pinned_objects = actor.pinned_statuses
                                   .includes(object: %i[actor media_attachments mentions tags poll])
                                   .ordered
                                   .map(&:object)

    return existing_pinned_objects if existing_pinned_objects.any?

    fetch_and_create_pinned(actor)
  end

  # 既存データを無視して最新のピン留めをフェッチ（stale refresh用）
  def fetch_for_actor_fresh(actor)
    return [] if actor.featured_url.blank?

    fetch_and_create_pinned(actor)
  end

  private

  def fetch_and_create_pinned(actor)
    Rails.logger.info "📌 Fetching featured collection for #{actor.username}@#{actor.domain}"

    collection_data = ActivityPubHttpClient.fetch_object(actor.featured_url)
    return [] unless collection_data

    featured_items = extract_featured_items(collection_data)
    Rails.logger.info "📌 Featured items found: #{featured_items.size}"

    pinned_objects = []
    featured_items.take(5).each do |item_uri|
      object = resolve_pinned_status(item_uri)
      next unless object

      pinned_objects << object
      create_pinned_status_record(actor, object)
    end

    Rails.logger.info "📌 Fetched #{pinned_objects.size} featured items for #{actor.username}@#{actor.domain}"
    pinned_objects
  rescue StandardError => e
    Rails.logger.error "❌ Failed to fetch featured collection: #{e.message}"
    []
  end

  def extract_featured_items(collection_data)
    items = []

    # OrderedCollectionまたはOrderedCollectionPageの場合
    if collection_data['orderedItems']
      items = collection_data['orderedItems']
    # Collectionの場合
    elsif collection_data['items']
      items = collection_data['items']
    end

    # itemsの内容を正規化：URIの文字列に変換
    items.filter_map do |item|
      case item
      when String
        item # すでにURIの文字列
      when Hash
        item['id'] || item['url'] # オブジェクトの場合はidまたはurlを抽出
      end
    end
  end

  def resolve_pinned_status(item_uri)
    # まず既存のオブジェクトがあるかチェック
    existing_object = ActivityPubObject.find_by(ap_id: item_uri)
    return existing_object if existing_object

    # リモートから取得する場合は、ピン留めフラグを付けて取得
    @resolver.resolve_remote_status_for_pinned(item_uri)
  end

  def create_pinned_status_record(actor, object)
    return if PinnedStatus.exists?(actor: actor, object: object)

    PinnedStatus.create!(
      actor: actor,
      object: object,
      position: actor.pinned_statuses.count
    )
  rescue StandardError => e
    Rails.logger.error "❌ Failed to create pinned status record: #{e.message}"
  end
end
