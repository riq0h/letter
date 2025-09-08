# frozen_string_literal: true

class StreamingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "🔗 StreamingChannel subscribed for user: #{current_user&.username}"
    Rails.logger.info '🔗 StreamingChannel ready for Mastodon client messages'

    # Mastodonクライアント向けの接続確認メッセージ
    transmit({ stream: ['user'], event: 'connected' })
    Rails.logger.info '🔗 Sent connected message to Mastodon client'
  end

  # Mastodon互換のメッセージ送信をオーバーライド
  def transmit(data, via: nil)
    # Action Cableの標準フォーマットではなく、Mastodonフォーマットで送信
    super
  end

  def unsubscribed
    Rails.logger.info "🔗 StreamingChannel unsubscribed for user: #{current_user&.username}"
    # クリーンアップ処理
  end

  # Mastodon互換のメッセージ受信処理
  def receive(data)
    Rails.logger.info "🔗 StreamingChannel received data: #{data}"

    message = data.is_a?(String) ? JSON.parse(data) : data

    case message['type']
    when 'subscribe'
      handle_subscribe(message)
    when 'unsubscribe'
      handle_unsubscribe(message)
    else
      Rails.logger.warn "🔗 Unknown message type: #{message['type']}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "🔗 Invalid JSON received: #{e.message}"
  end

  private

  def handle_subscribe(message)
    stream_type = message['stream']
    Rails.logger.info "🔗 Subscribing to stream: #{stream_type}"

    case stream_type
    when 'user'
      stream_for_user
      transmit({ event: 'stream', stream: ['user'], payload: 'subscribed' })
    when 'public'
      stream_from 'timeline:public'
      transmit({ event: 'stream', stream: ['public'], payload: 'subscribed' })
    when 'public:local'
      stream_from 'timeline:public:local'
      transmit({ event: 'stream', stream: %w[public local], payload: 'subscribed' })
    when 'hashtag'
      stream_hashtag(message['tag'], local_only: false)
      transmit({ event: 'stream', stream: ['hashtag'], payload: 'subscribed' })
    when 'hashtag:local'
      stream_hashtag(message['tag'], local_only: true)
      transmit({ event: 'stream', stream: %w[hashtag local], payload: 'subscribed' })
    when /\Alist:\d+\z/
      stream_list(stream_type.split(':').last)
      transmit({ event: 'stream', stream: [stream_type], payload: 'subscribed' })
    else
      Rails.logger.warn "🔗 Unknown stream type: #{stream_type}"
      transmit({ event: 'error', error: 'Unknown stream type' })
    end
  end

  def handle_unsubscribe(message)
    stream_type = message['stream']
    Rails.logger.info "🔗 Unsubscribing from stream: #{stream_type}"
    # Action Cableでは明示的なunsubscribeは不要（接続終了時に自動的に処理される）
    transmit({ event: 'stream', stream: [stream_type], payload: 'unsubscribed' })
  end

  def stream_for_user
    # ユーザ固有のストリーム
    stream_from "timeline:user:#{current_user.id}"

    # ホームタイムライン（フォロー中のユーザ）
    stream_from "timeline:home:#{current_user.id}"

    # 通知ストリーム
    stream_from "notifications:#{current_user.id}"
  end

  def stream_hashtag(hashtag, local_only: false)
    return reject if hashtag.blank?

    normalized_hashtag = hashtag.to_s.downcase
    stream_name = local_only ? "hashtag:#{normalized_hashtag}:local" : "hashtag:#{normalized_hashtag}"
    stream_from stream_name
  end

  def stream_list(list_id)
    list = current_user.lists.find_by(id: list_id)
    return reject unless list

    stream_from "list:#{list_id}"
  end
end
