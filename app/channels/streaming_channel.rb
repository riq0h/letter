# frozen_string_literal: true

class StreamingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "🔗 StreamingChannel subscribed for user: #{current_user&.username}"
    # Mastodon互換：接続確認メッセージを送信
    transmit({ event: 'connected' })
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
    when /\Ahashtag(?::local)?\z/
      stream_hashtag(stream_type.include?('local'))
      transmit({ event: 'stream', stream: [stream_type], payload: 'subscribed' })
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

  def stream_hashtag(local_only: false)
    hashtag = params[:tag]&.downcase
    return reject if hashtag.blank?

    stream_name = local_only ? "hashtag:#{hashtag}:local" : "hashtag:#{hashtag}"
    stream_from stream_name
  end

  def stream_list(list_id)
    list = current_user.lists.find_by(id: list_id)
    return reject unless list

    stream_from "list:#{list_id}"
  end
end
