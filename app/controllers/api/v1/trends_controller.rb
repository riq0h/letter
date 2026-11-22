# frozen_string_literal: true

module Api
  module V1
    class TrendsController < Api::BaseController
      # 直近7日に他サーバの投稿で使われたタグを、使ったアカウント数の多い順に返す
      # (Mastodonのトレンドと同じ考え方)。集計は重いので結果を1時間使い回す
      TRENDS_WINDOW = 7.days
      TRENDS_CACHE_TTL = 1.hour
      MAX_TRENDING_TAGS = 20

      include StatusSerializationHelper
      include AccountSerializer
      include TagSerializer

      before_action :doorkeeper_authorize!

      # GET /api/v1/trends
      def index
        # デフォルトではタグのトレンドを返す
        render_trending_tags
      end

      # GET /api/v1/trends/tags
      def tags
        render_trending_tags
      end

      # GET /api/v1/trends/statuses
      def statuses
        render json: []
      end

      # GET /api/v1/trends/links
      def links
        # letterでは外部リンクのトレンド機能は簡素化
        # 空配列を返す
        render json: []
      end

      private

      def render_trending_tags
        limit = [params[:limit].to_i, MAX_TRENDING_TAGS].min
        limit = 10 if limit <= 0

        trending_tags = generate_trending_tags(limit)
        render json: trending_tags.map { |tag| serialized_tag(tag, include_history: true) }
      end

      def generate_trending_tags(limit)
        ids = Rails.cache.fetch('api:v1:trends:tag_ids', expires_in: TRENDS_CACHE_TTL) { trending_tag_ids }.first(limit)
        tags = Tag.where(id: ids).index_by(&:id)
        ids.filter_map { |id| tags[id] }
      end

      # 投稿テーブルは大きいので、直近に付いたタグ(object_tags)から絞ってから他サーバの投稿かを見る
      def trending_tag_ids
        ObjectTag.joins(:object)
                 .where(created_at: TRENDS_WINDOW.ago.., objects: { local: false })
                 .group(:tag_id)
                 .order(Arel.sql('COUNT(DISTINCT objects.actor_id) DESC, COUNT(*) DESC'))
                 .limit(MAX_TRENDING_TAGS)
                 .pluck(:tag_id)
      end

      # AccountSerializer から継承されたメソッドを使用
    end
  end
end
