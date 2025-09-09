# frozen_string_literal: true

class StreamingChannel < ApplicationCable::Channel
  def subscribed
    Rails.logger.info "StreamingChannel subscribed for user: #{current_user&.username}"
  end

  def transmit(data, _via = nil)
    return true if try_websocket_method(data)
    return true if try_websocket_instance_var(data)
    return true if try_websocket_send_async(data)

    fallback_transmit(data)
  end

  def unsubscribed
    Rails.logger.info "StreamingChannel unsubscribed for user: #{current_user&.username}"
  end

  def receive(data)
    message = data.is_a?(String) ? JSON.parse(data) : data

    case message['type']
    when 'subscribe'
      handle_subscribe(message)
    when 'unsubscribe'
      handle_unsubscribe(message)
    end
  rescue JSON::ParserError => e
    Rails.logger.error "Invalid JSON received: #{e.message}"
  end

  private

  def handle_subscribe(message)
    stream_type = message['stream']

    case stream_type
    when 'user'
      stream_for_user
    when 'public'
      stream_from 'timeline:public'
    when 'public:local'
      stream_from 'timeline:public:local'
    when 'hashtag'
      stream_hashtag(message['tag'], local_only: false)
    when 'hashtag:local'
      stream_hashtag(message['tag'], local_only: true)
    when /\Alist:\d+\z/
      stream_list(stream_type.split(':').last)
    end
  end

  def handle_unsubscribe(message)
    # Action Cableでは明示的なunsubscribeは不要
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

  def try_websocket_method(data)
    websocket = connection.send(:websocket)
    return false unless websocket.respond_to?(:transmit)

    websocket.transmit(data.to_json)
    true
  rescue StandardError
    false
  end

  def try_websocket_instance_var(data)
    websocket = connection.instance_variable_get(:@websocket)
    return false unless websocket.respond_to?(:transmit)

    websocket.transmit(data.to_json)
    true
  rescue StandardError
    false
  end

  def try_websocket_send_async(data)
    connection.send_async(:websocket_transmit, data.to_json)
    true
  rescue StandardError
    false
  end

  def fallback_transmit(data)
    super(data.to_json)
    false
  end
end
