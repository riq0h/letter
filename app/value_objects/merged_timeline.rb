# frozen_string_literal: true

# タイムラインのマージを行うValueObject
# ステータスとリブログを時系列で統合し、重複を除去する
class MergedTimeline
  attr_reader :items, :limit

  def initialize(statuses, reblogs, limit)
    @statuses = statuses
    @reblogs = reblogs
    @limit = limit
    @items = merge_timelines
    freeze
  end

  # ファクトリメソッド
  def self.merge(statuses, reblogs, limit)
    new(statuses, reblogs, limit)
  end

  # Enumerableメソッドを委譲
  delegate :count, :empty?, to: :items

  # 配列として扱えるようにする
  def to_a
    items
  end

  delegate :each, :map, :select, :reject, :first, :last, to: :items

  # 文字列表現
  def to_s
    "MergedTimeline(#{count} items)"
  end

  # 等価性の判定
  def ==(other)
    return false unless other.is_a?(MergedTimeline)

    items == other.items && limit == other.limit
  end

  alias eql? ==

  def hash
    [items, limit].hash
  end

  private

  attr_reader :statuses, :reblogs

  def merge_timelines
    status_array = statuses.to_a
    reblog_array = reblogs.to_a

    return [] if status_array.empty? && reblog_array.empty?

    seen_status_ids = Set.new
    merged_items = []

    all_items = build_timeline_items(status_array, reblog_array)
    all_items.sort_by! { |item| -item[:timestamp].to_f }

    process_timeline_items(all_items, seen_status_ids, merged_items)
    merged_items
  end

  def build_timeline_items(status_array, reblog_array)
    items = status_array.map do |status|
      {
        item: status,
        timestamp: status.published_at,
        is_reblog: false,
        status_id: status.id
      }
    end

    reblog_array.each do |reblog|
      items << {
        item: reblog,
        timestamp: reblog.created_at,
        is_reblog: true,
        status_id: reblog.object_id
      }
    end

    items
  end

  def process_timeline_items(all_items, seen_status_ids, merged_items)
    all_items.each do |item_data|
      status_id = item_data[:status_id]

      next if seen_status_ids.include?(status_id)

      seen_status_ids.add(status_id)
      merged_items << item_data[:item]
      break if merged_items.length >= limit
    end
  end
end
