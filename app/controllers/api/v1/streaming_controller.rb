# frozen_string_literal: true

module Api
  module V1
    class StreamingController < Api::BaseController
      include ActionController::Live

      before_action :doorkeeper_authorize!
      before_action :set_cors_headers

      def index
        if sse_request?
          serve_sse_stream
        else
          serve_polling_response
        end
      end

      private

      def sse_request?
        request.headers['Accept']&.include?('text/event-stream') ||
          params[:stream_format] == 'sse'
      end

      def serve_sse_stream
        response.headers['Content-Type'] = 'text/event-stream'
        response.headers['Cache-Control'] = 'no-cache'
        response.headers['Connection'] = 'keep-alive'
        response.headers['X-Accel-Buffering'] = 'no'

        # SSE接続オブジェクトを作成
        connection = SseConnection.new(response.stream, current_user, params[:stream])

        # 接続管理システムに登録
        SseConnectionManager.instance.register_connection(current_user.id, params[:stream], connection)

        logger.info "🔗 Real-time SSE streaming started for #{current_user.username}: #{params[:stream]}"

        begin
          # ウェルカムメッセージ送信
          connection.send_welcome_message

          # 初期データ送信（最近の履歴）
          send_initial_events(connection)

          # Keep-alive（ハートビートのみ、データベースポーリング廃止）
          loop do
            connection.send_heartbeat
            sleep 30 # 30秒間隔のハートビート
          end
        rescue IOError, Errno::EPIPE, Errno::ECONNRESET
          logger.info "SSE client disconnected: #{current_user.username}"
        rescue StandardError => e
          logger.error "SSE streaming error: #{e.message}"
          logger.error "Backtrace: #{e.backtrace[0..2].join(', ')}"
        ensure
          connection.close
        end
      end

      def serve_polling_response
        # ポーリングレスポンスも認証が必要
        unless current_user
          render json: { error: 'Authentication required for streaming' }, status: :unauthorized
          return
        end

        events = fetch_events_since(params[:since_id].to_i)
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
                                 .includes(:media_attachments)
                                 .recent
                                 .limit(20)

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
                                 .includes(:actor, :media_attachments)
                                 .recent
                                 .limit(20)

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
                                 .includes(:actor, :media_attachments)
                                 .recent
                                 .limit(20)

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

        tag = Tag.find_by(name: hashtag.downcase)
        return [] unless tag

        posts = tag.objects.joins(:actor)
                   .where('objects.id > ?', since_id)
                   .where(visibility: 'public', object_type: 'Note')
                   .where(local_only ? { local: true } : {})
                   .includes(:actor, :media_attachments)
                   .recent
                   .limit(20)

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
                                 .includes(:actor, :media_attachments)
                                 .recent
                                 .limit(20)

        posts.map do |post|
          {
            id: post.id,
            event: 'update',
            payload: serialize_status(post).to_json
          }
        end
      end

      def send_initial_events(connection)
        # 過去の投稿を少し送信（履歴として10件程度）
        events = fetch_events_since(0).last(10)
        events.each do |event|
          connection.send_event(event[:event], event[:payload])
        end

        logger.debug "📤 Sent #{events.size} initial events to #{current_user.username}:#{params[:stream]}"
      end

      def serialize_status(status)
        serialized_status(status)
      end

      def serialize_notification(notification)
        NotificationSerializer.new(notification).as_json
      end

      def set_cors_headers
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type'
      end
    end
  end
end
