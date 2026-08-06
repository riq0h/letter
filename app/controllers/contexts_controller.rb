# frozen_string_literal: true

# FEP-7888: 会話contextコレクションの配信。
# ローカル投稿をルートとするスレッドの構成員(ap_id)一覧を返し、
# 他サーバがスレッド全体をバックフィルできるようにする
class ContextsController < ApplicationController
  include ErrorResponseHelper

  skip_before_action :verify_authenticity_token

  MAX_ITEMS = 500
  MAX_DEPTH = 5

  def show
    root = ActivityPubObject.find_by(id: params[:id], local: true)

    unless root && %w[public unlisted].include?(root.visibility)
      render_not_found('Context')
      return
    end

    items = collect_thread_ap_ids(root)

    collection = {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => "#{activitypub_base_url}/contexts/#{root.id}",
      'type' => 'OrderedCollection',
      'attributedTo' => root.actor.ap_id,
      'totalItems' => items.size,
      'orderedItems' => items
    }

    render json: collection, content_type: 'application/activity+json; charset=utf-8'
  end

  private

  # ルートから返信を幅優先で辿り、公開範囲のものだけを集める
  def collect_thread_ap_ids(root)
    items = [root.ap_id]
    frontier = [root.ap_id]

    MAX_DEPTH.times do
      break if frontier.empty? || items.size >= MAX_ITEMS

      replies = ActivityPubObject.where(in_reply_to_ap_id: frontier)
                                 .where(visibility: %w[public unlisted])
                                 .order(:published_at)
                                 .limit(MAX_ITEMS - items.size)
                                 .pluck(:ap_id)
      items.concat(replies)
      frontier = replies
    end

    items
  end
end
