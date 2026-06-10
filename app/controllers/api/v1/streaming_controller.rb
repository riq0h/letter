# frozen_string_literal: true

module Api
  module V1
    # ストリーミングAPIのポーリング実装。
    # かつてのSSE実装は撤去した: Mastodon系クライアントはWebSocket前提のため
    # SSEには誰も接続できず（稼働ログ6日間で接続ゼロ）、1接続がpumaスレッドを
    # 最大10分占有する設計はスレッド枯渇のリスクでしかなかった。
    # リアルタイム配信を将来実装する場合はSolid CableによるWebSocketが筋
    class StreamingController < Api::BaseController
      include StatusSerializationHelper

      before_action :doorkeeper_authorize!
      before_action :set_cors_headers

      def index
        serve_polling_response
      end

      private

      def serve_polling_response
        # ポーリングレスポンスも認証が必要
        unless current_user
          render_authentication_required
          return
        end

        events = fetch_events_since(params[:since_id].to_s)
        render json: events
      end

      def fetch_events_since(since_id)
        case params[:stream]
        when 'user'
          fetch_user_timeline_events(since_id)
        when 'public'
          fetch_public_timeline_events(since_id)
        when 'public:local'
          fetch_local_timeline_events(since_id)
        when /\Ahashtag\z/
          fetch_hashtag_events(params[:tag], since_id, local_only: false)
        when /\Ahashtag:local\z/
          fetch_hashtag_events(params[:tag], since_id, local_only: true)
        when /\Alist:\d+\z/
          fetch_list_events(params[:stream].split(':').last.to_i, since_id)
        else
          []
        end
      end

      def fetch_user_timeline_events(since_id)
        # ユーザ自身の投稿
        user_posts = current_user.objects
                                 .where('id > ?', since_id)
                                 .where(object_type: 'Note')
                                 .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                 .recent
                                 .limit(20)
                                 .to_a

        preload_all_status_data(user_posts)

        events = user_posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end

        events.sort_by { |e| e[:id] }
      end

      def fetch_public_timeline_events(since_id)
        posts = ActivityPubObject.joins(:actor)
                                 .where('objects.id > ?', since_id)
                                 .where(visibility: 'public', object_type: 'Note')
                                 .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                 .recent
                                 .limit(20)
                                 .to_a

        preload_all_status_data(posts)

        posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end
      end

      def fetch_local_timeline_events(since_id)
        posts = ActivityPubObject.joins(:actor)
                                 .where('objects.id > ?', since_id)
                                 .where(visibility: 'public', object_type: 'Note', local: true)
                                 .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                 .recent
                                 .limit(20)
                                 .to_a

        preload_all_status_data(posts)

        posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end
      end

      def fetch_hashtag_events(hashtag, since_id, local_only:)
        return [] if hashtag.blank?

        tag = Tag.find_by(name: hashtag.unicode_normalize(:nfkc).strip.downcase)
        return [] unless tag

        posts = tag.objects.joins(:actor)
                   .where('objects.id > ?', since_id)
                   .where(visibility: 'public', object_type: 'Note')
                   .where(local_only ? { local: true } : {})
                   .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                   .recent
                   .limit(20)
                   .to_a

        preload_all_status_data(posts)

        posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end
      end

      def fetch_list_events(list_id, since_id)
        list = current_user.lists.find_by(id: list_id)
        return [] unless list

        # リストメンバーの投稿を取得
        member_ids = list.list_memberships.pluck(:actor_id)
        posts = ActivityPubObject.joins(:actor)
                                 .where('objects.id > ?', since_id)
                                 .where(actor_id: member_ids)
                                 .where(object_type: 'Note')
                                 .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                 .recent
                                 .limit(20)
                                 .to_a

        preload_all_status_data(posts)

        posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end
      end

      def serialize_status(status)
        serialized_status(status)
      end

      def set_cors_headers
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
      end
    end
  end
end
