# frozen_string_literal: true

module Api
  module V1
    class TimelinesController < Api::BaseController
      include StatusSerializationHelper
      include ApiPagination

      before_action :doorkeeper_authorize!, only: %i[home list]
      after_action :insert_pagination_headers

      # GET /api/v1/timelines/home
      def home
        return render_authentication_required unless current_user

        timeline_query = TimelineQuery.new(current_user, timeline_params)
        timeline_items = timeline_query.build_home_timeline

        # リプライ先情報とインタラクション状態をプリロード
        statuses = timeline_items.filter_map { |item| item.is_a?(Reblog) ? item.object : item }
        preload_all_status_data(statuses)

        @paginated_items = timeline_items
        render json: timeline_items.map { |item| serialize_timeline_item(item) }
      end

      # GET /api/v1/timelines/public
      def public
        timeline_query = TimelineQuery.new(current_user, timeline_params)
        statuses = timeline_query.build_public_timeline

        preload_all_status_data(statuses)

        @paginated_items = statuses
        render json: statuses.map { |status| serialized_status(status) }
      end

      # GET /api/v1/timelines/tag/:hashtag
      def tag
        timeline_query = TimelineQuery.new(current_user, timeline_params)
        statuses = timeline_query.build_hashtag_timeline(params[:hashtag])

        preload_all_status_data(statuses)

        @paginated_items = statuses
        render json: statuses.map { |status| serialized_status(status) }
      end

      # GET /api/v1/timelines/list/:id
      def list
        return render_authentication_required unless current_user

        list = current_user.lists.find_by(id: params[:id])
        return render_not_found('List') unless list

        timeline_query = TimelineQuery.new(current_user, timeline_params)
        statuses = timeline_query.build_list_timeline(list)

        preload_all_status_data(statuses)

        @paginated_items = statuses
        render json: statuses.map { |status| serialized_status(status) }
      end

      private

      def timeline_params
        params.permit(:max_id, :since_id, :min_id, :local).merge(limit: limit_param)
      end

      def serialize_timeline_item(item)
        case item
        when Reblog
          # リブログ - リブログされた元投稿をラップして返す
          reblogged_status = serialized_status(item.object)
          reblogged_status[:reblog] = nil # ネストしたリブログを防ぐ

          # リブログ情報を追加
          {
            id: item.timeline_id,
            created_at: item.created_at.iso8601,
            account: serialized_account(item.actor),
            reblog: reblogged_status
          }.merge(default_interaction_data)
        else
          # 通常のステータスまたはActivityPubObject
          serialized_status(item)
        end
      end

      def default_interaction_data
        {
          favourited: false,
          reblogged: false,
          muted: false,
          bookmarked: false,
          pinned: false,
          content: '',
          visibility: 'public',
          sensitive: false,
          spoiler_text: '',
          url: '',
          uri: '',
          in_reply_to_id: nil,
          in_reply_to_account_id: nil,
          media_attachments: [],
          mentions: [],
          tags: [],
          emojis: [],
          reblogs_count: 0,
          favourites_count: 0,
          replies_count: 0,
          language: nil,
          text: nil,
          edited_at: nil,
          poll: nil,
          card: nil,
          quote: nil
        }
      end
    end
  end
end
