# frozen_string_literal: true

module Streaming
  # 出来事を、受け取る人から見たMastodon APIの形(JSON文字列)にする。お気に入り済みかどうかなどは
  # 人ごとに違うので人ごとに作り、同じものは1度だけ組み立てる。見せないものはnilを返す
  class Renderer
    include TimelineItemSerializer
    include NotificationHelper
    include ConversationSerializer

    STATUS_INCLUDES = {
      actor: { avatar_attachment: :blob, header_attachment: :blob },
      media_attachments: { file_attachment: :blob, thumbnail_attachment: :blob },
      poll: [], tags: [],
      mentions: { actor: { avatar_attachment: :blob, header_attachment: :blob } }
    }.freeze

    attr_reader :current_user

    def initialize(user)
      @current_user = user
      @memo = {}
    end

    # ホームに加わった投稿かブースト。ホームのタイムラインに出さないものならnil
    def home_item(sort_id)
      memoize(:home_item, sort_id) do
        item = timeline_query.home_feed_item(sort_id)
        next unless item

        preload_all_status_data([item.is_a?(Reblog) ? item.object : item])
        serialize_timeline_item(item).to_json
      end
    end

    # 編集された投稿。この人のホームに(ブーストされた形も含めて)出ているものだけ
    def home_status(status_id)
      return unless memoize(:in_home, status_id) { timeline_query.home_feed_includes?(status_id) }

      status(status_id)
    end

    # 購読しているタイムラインに載る投稿
    def timeline_status(subscription, status_id)
      return unless in_timeline?(subscription, status_id)

      status(status_id)
    end

    def status(status_id)
      memoize(:status, status_id) do
        status = ActivityPubObject.includes(STATUS_INCLUDES).find_by(id: status_id)
        next unless status&.visible_to?(current_user)

        preload_all_status_data([status])
        serialized_status(status).to_json
      end
    end

    def notification(notification_id)
      memoize(:notification, notification_id) do
        notification = current_user.notifications.find_by(id: notification_id)
        next unless notification

        objects = preload_activity_pub_objects([notification])
        preload_all_status_data(objects.values) if objects.any?
        notification_json_with_preloaded(notification, objects).to_json
      end
    end

    def conversation(conversation_id)
      memoize(:conversation, conversation_id) do
        conversation = Conversation.for_actor(current_user).includes(:participants, :last_status)
                                   .find_by(id: conversation_id)
        next unless conversation

        preload_all_status_data([conversation.last_status]) if conversation.last_status
        serialized_conversation(conversation).to_json
      end
    end

    private

    # シリアライザの一部はリクエストの引数を見る。リクエストの外なので空
    def params
      {}
    end

    def timeline_query(local: false)
      TimelineQuery.new(current_user, local ? { local: 'true' } : {})
    end

    # REST APIのタイムラインと同じ条件で、投稿がそのタイムラインに載るかを確かめる
    def in_timeline?(subscription, status_id)
      memoize(:in_timeline, subscription.name, status_id) do
        scope = timeline_scope(subscription)
        scope = scope.where(local: true) if subscription.hashtag? && subscription.local_only?
        scope = scope.where(local: false) if subscription.remote_only?
        next false unless scope.except(:includes, :order, :limit).exists?(id: status_id)

        !subscription.media_only? || MediaAttachment.exists?(object_id: status_id)
      end
    end

    def timeline_scope(subscription)
      query = timeline_query(local: subscription.public_timeline? && subscription.local_only?)
      if subscription.public_timeline?
        query.public_timeline_scope
      elsif subscription.hashtag?
        query.hashtag_timeline_scope(subscription.param)
      else
        list = current_user.lists.find_by(id: subscription.param)
        list ? query.list_timeline_scope(list) : ActivityPubObject.none
      end
    end

    def memoize(*key)
      return @memo[key] if @memo.key?(key)

      @memo[key] = yield
    end
  end
end
