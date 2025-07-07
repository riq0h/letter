# frozen_string_literal: true

module Api
  module V1
    class TrendsController < Api::BaseController
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
        limit = [params[:limit].to_i, 20].min
        limit = 10 if limit <= 0

        trending_tags = generate_trending_tags(limit)
        render json: trending_tags.map { |tag| serialized_tag(tag, include_history: true) }
      end

      def generate_trending_tags(limit)
        # letterでは簡素化されたトレンド機能
        # リモート投稿から使用されたタグを使用回数順で返す（ローカル投稿は除外）
        Tag.joins('JOIN object_tags ON tags.id = object_tags.tag_id')
           .joins('JOIN objects ON object_tags.object_id = objects.id')
           .where('objects.local = ? AND tags.usage_count > 0', false)
           .group('tags.id')
           .order('tags.usage_count DESC, tags.updated_at DESC')
           .limit(limit)
      end

      def generate_trending_statuses(limit)
        # リモート投稿から人気の高いものを返す（ローカル投稿は除外）
        # いいねやリブログが多い投稿を基準とする
        ActivityPubObject.where(object_type: 'Note', local: false)
                         .includes(:poll)
                         .joins('LEFT JOIN favourites ON favourites.object_id = objects.id')
                         .joins('LEFT JOIN reblogs ON reblogs.object_id = objects.id')
                         .where('objects.published_at > ?', 7.days.ago)
                         .group('objects.id')
                         .order(Arel.sql('COUNT(favourites.id) + COUNT(reblogs.id) DESC, objects.published_at DESC'))
                         .limit(limit)
      end

      # AccountSerializer から継承されたメソッドを使用
    end
  end
end
