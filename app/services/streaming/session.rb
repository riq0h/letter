# frozen_string_literal: true

module Streaming
  # 接続1本分のやり取り。メッセージの形はMastodonのストリーミングと同じで、クライアントは
  # {"type":"subscribe","stream":"user"} のように購読し、
  # {"stream":["user"],"event":"update","payload":"<StatusのJSON>"} の形で受け取る。
  # 通信の手段(WebSocket)とは切り離してあり、送るのはtransport.send_textに任せる
  class Session
    MAX_SUBSCRIPTIONS = 100

    # 宛先が決まっている出来事と、それを受け取るストリーム
    PERSONAL_STREAMS = {
      'home' => %w[user],
      'notification' => %w[user user:notification],
      'conversation' => %w[direct]
    }.freeze

    attr_reader :user

    def initialize(user:, scopes:, transport:, on_change: nil)
      @user = user
      @scopes = scopes
      @transport = transport
      @on_change = on_change
      @subscriptions = []
      @lock = Mutex.new
    end

    # 接続のURLで指定された購読(?stream=user など)
    def open(params)
      subscribe(params) if params['stream'].present?
    end

    def receive(text)
      message = JSON.parse(text)
      return unless message.is_a?(Hash)

      case message['type']
      when 'subscribe' then subscribe(message)
      when 'unsubscribe' then unsubscribe(message)
      end
    rescue JSON::ParserError
      nil
    end

    def subscriptions
      @lock.synchronize { @subscriptions.dup }
    end

    def timelines?
      subscriptions.any?(&:timeline?)
    end

    # 出来事を、それが届くストリームごとに送る
    def deliver(event, renderer)
      subscriptions.each do |subscription|
        name, payload = message_for(event, subscription, renderer)
        next unless payload

        @transport.send_text({ stream: subscription.name, event: name, payload: payload }.to_json)
      end
    end

    private

    def subscribe(params)
      subscription = Subscription.build(user, @scopes, stream: params['stream'], tag: params['tag'], list: params['list'])
      added = @lock.synchronize do
        next false if @subscriptions.include?(subscription) || @subscriptions.size >= MAX_SUBSCRIPTIONS

        @subscriptions << subscription
      end
      @on_change&.call if added
    rescue Subscription::Invalid => e
      @transport.send_text({ error: e.message, status: e.status }.to_json)
    end

    def unsubscribe(params)
      stream = params['stream'].to_s
      param = (stream.start_with?('hashtag') ? params['tag'] : params['list'])&.to_s
      @lock.synchronize { @subscriptions.delete(Subscription.new(stream, param.presence)) }
    end

    # この購読に送るイベント名と中身。送らないならnil
    def message_for(event, subscription, renderer)
      case event.kind
      when 'home', 'notification', 'conversation'
        personal_message(event, subscription, renderer)
      when 'status'
        ['update', renderer.timeline_status(subscription, event.target_id)] if subscription.timeline?
      when 'status.update'
        ['status.update', updated_status(event, subscription, renderer)]
      when 'delete'
        ['delete', event.target_id] if delete_reaches?(event, subscription)
      end
    end

    def personal_message(event, subscription, renderer)
      return unless event.recipient_id == user.id
      return unless PERSONAL_STREAMS[event.kind].include?(subscription.stream)

      case event.kind
      when 'home' then ['update', renderer.home_item(event.target_id)]
      when 'notification' then ['notification', renderer.notification(event.target_id)]
      when 'conversation' then ['conversation', renderer.conversation(event.target_id)]
      end
    end

    def updated_status(event, subscription, renderer)
      if subscription.timeline?
        renderer.timeline_status(subscription, event.target_id)
      elsif subscription.stream == 'user'
        renderer.home_status(event.target_id)
      end
    end

    # 消えた投稿のIDは、それが出ていたかもしれないストリームに送る(クライアントは知らないIDなら無視する)。
    # 公開のタイムラインとハッシュタグには、公開の投稿だったときだけ送る
    def delete_reaches?(event, subscription)
      return true if %w[user list].include?(subscription.stream)
      return event.public_visibility if subscription.public_timeline? || subscription.hashtag?

      false
    end
  end
end
