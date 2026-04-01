# frozen_string_literal: true

module StatusContextBuilder
  extend ActiveSupport::Concern

  private

  def build_ancestors(status)
    return [] unless status.in_reply_to_ap_id

    # まずap_idチェーンを辿ってIDを収集
    ap_ids = []
    current_ap_id = status.in_reply_to_ap_id
    max_depth = 10

    max_depth.times do
      break if current_ap_id.blank?

      ap_ids << current_ap_id
      parent = ActivityPubObject.select(:in_reply_to_ap_id).find_by(ap_id: current_ap_id)
      break unless parent

      current_ap_id = parent.in_reply_to_ap_id
    end

    return [] if ap_ids.empty?

    # 一括取得してap_id順に並べ替え
    objects = ActivityPubObject.where(ap_id: ap_ids)
                               .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                               .index_by(&:ap_id)

    ap_ids.reverse.filter_map { |ap_id| objects[ap_id] }
  rescue StandardError
    []
  end

  def build_descendants(status)
    # 直接的な返信を取得
    direct_replies = ActivityPubObject.where(in_reply_to_ap_id: status.ap_id)
                                      .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                      .order(:published_at)

    descendants = []

    # 各返信を再帰的に処理（最大深度制限）
    direct_replies.each do |reply|
      descendants << reply
      descendants.concat(build_descendants_recursive(reply, 1, 5))
    end

    descendants
  rescue StandardError
    []
  end

  def build_descendants_recursive(status, current_depth, max_depth)
    return [] if current_depth >= max_depth

    replies = ActivityPubObject.where(in_reply_to_ap_id: status.ap_id)
                               .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                               .order(:published_at)

    descendants = []
    replies.each do |reply|
      descendants << reply
      descendants.concat(build_descendants_recursive(reply, current_depth + 1, max_depth))
    end

    descendants
  rescue StandardError
    []
  end
end
