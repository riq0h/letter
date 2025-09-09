# frozen_string_literal: true

class StreamingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "🔗 StreamingChannel subscribed for user: #{current_user&.username}"
    Rails.logger.info '🔗 StreamingChannel ready for Mastodon client messages'
  end

  # Mastodon互換のメッセージ送信をオーバーライド
  def transmit(data, _via = nil)
    Rails.logger.info '🔗 Attempting direct WebSocket transmission'

    return true if try_websocket_method(data)
    return true if try_websocket_instance_var(data)
    return true if try_websocket_send_async(data)

    fallback_transmit(data)
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
      Rails.logger.info '🔗 User stream subscribed successfully'
    when 'public'
      stream_from 'timeline:public'
      Rails.logger.info '🔗 Public stream subscribed successfully'
    when 'public:local'
      stream_from 'timeline:public:local'
      Rails.logger.info '🔗 Local public stream subscribed successfully'
    when 'hashtag'
      stream_hashtag(message['tag'], local_only: false)
      Rails.logger.info "🔗 Hashtag stream subscribed successfully: #{message['tag']}"
    when 'hashtag:local'
      stream_hashtag(message['tag'], local_only: true)
      Rails.logger.info "🔗 Local hashtag stream subscribed successfully: #{message['tag']}"
    when /\Alist:\d+\z/
      stream_list(stream_type.split(':').last)
      Rails.logger.info "🔗 List stream subscribed successfully: #{stream_type}"
    else
      Rails.logger.warn "🔗 Unknown stream type: #{stream_type}"
    end
  end

  def handle_unsubscribe(message)
    stream_type = message['stream']
    Rails.logger.info "🔗 Unsubscribing from stream: #{stream_type}"
    # Action Cableでは明示的なunsubscribeは不要（接続終了時に自動的に処理される）
    Rails.logger.info "🔗 Stream unsubscribed successfully: #{stream_type}"
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

  # WebSocket直接送信メソッド群
  def try_websocket_method(data)
    websocket = connection.send(:websocket)
    return false unless websocket.respond_to?(:transmit)

    websocket.transmit(data.to_json)
    Rails.logger.info "🔗 Direct WebSocket (method) message sent: #{data.to_json}"
    true
  rescue StandardError => e
    Rails.logger.warn "🔗 WebSocket method access failed: #{e.message}"
    false
  end

  def try_websocket_instance_var(data)
    websocket = connection.instance_variable_get(:@websocket)
    return false unless websocket.respond_to?(:transmit)

    websocket.transmit(data.to_json)
    Rails.logger.info "🔗 Direct WebSocket (instance var) message sent: #{data.to_json}"
    true
  rescue StandardError => e
    Rails.logger.warn "🔗 WebSocket instance variable access failed: #{e.message}"
    false
  end

  def try_websocket_send_async(data)
    connection.send_async(:websocket_transmit, data.to_json)
    Rails.logger.info "🔗 Direct WebSocket (send_async) message sent: #{data.to_json}"
    true
  rescue StandardError => e
    Rails.logger.warn "🔗 WebSocket send_async failed: #{e.message}"
    false
  end

  def fallback_transmit(data)
    Rails.logger.warn '🔗 All direct methods failed, using Action Cable transmit'
    super(data.to_json)
    Rails.logger.info "🔗 Fallback Action Cable message sent: #{data.to_json}"
    false
  end
end
