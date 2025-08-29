# frozen_string_literal: true

module Api
  module V1
    class TimelinesController < Api::BaseController
      include StatusSerializationHelper
      include AccountSerializer
      include TextLinkingHelper
      include ApiPagination

      before_action :doorkeeper_authorize!, only: [:home]
      after_action :insert_pagination_headers

      # GET /api/v1/timelines/home
      def home
        return render_authentication_required unless current_user

        timeline_query = TimelineQuery.new(current_user, timeline_params)
        timeline_items = timeline_query.build_home_timeline

        @paginated_items = timeline_items
        render json: timeline_items.map { |item| serialize_timeline_item(item) }
      end

      # GET /api/v1/timelines/public
      def public
        timeline_query = TimelineQuery.new(current_user, timeline_params)
        statuses = timeline_query.build_public_timeline

        @paginated_items = statuses
        render json: statuses.map { |status| serialized_status(status) }
      end

      # GET /api/v1/timelines/tag/:hashtag
      def tag
        timeline_query = TimelineQuery.new(current_user, timeline_params)
        statuses = timeline_query.build_hashtag_timeline(params[:hashtag])

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
            id: item.id.to_s,
            created_at: item.created_at.iso8601,
            account: simple_account_data(item.actor),
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
          poll: nil
        }
      end

      def simple_account_data(actor)
        {
          id: actor.id.to_s,
          username: actor.username,
          acct: actor.local? ? actor.username : actor.full_username,
          display_name: actor.display_name || actor.username,
          locked: actor.manually_approves_followers || false,
          bot: actor.actor_type == 'Service',
          discoverable: actor.discoverable || false,
          group: false,
          created_at: actor.created_at.iso8601,
          note: actor.note || '',
          url: actor.public_url || actor.ap_id || '',
          uri: actor.ap_id || '',
          avatar: actor.avatar_url || '/icon.png',
          avatar_static: actor.avatar_url || '/icon.png',
          header: actor.header_url || '/icon.png',
          header_static: actor.header_url || '/icon.png',
          followers_count: actor.followers_count || 0,
          following_count: actor.following_count || 0,
          statuses_count: actor.posts_count || 0,
          last_status_at: nil,
          emojis: [],
          fields: []
        }
      end
    end
  end
end
