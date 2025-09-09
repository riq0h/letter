# frozen_string_literal: true

class SseConnectionManager
  include Singleton

  def initialize
    @connections = {}
    @mutex = Mutex.new
  end

  def register_connection(user_id, stream_type, connection)
    @mutex.synchronize do
      key = connection_key(user_id, stream_type)
      @connections[key] ||= []
      @connections[key] << connection
      Rails.logger.info "🔗 SSE connection registered: #{key} (total: #{@connections[key].size})"
    end
  end

  def unregister_connection(user_id, stream_type, connection)
    @mutex.synchronize do
      key = connection_key(user_id, stream_type)
      @connections[key]&.delete(connection)
      if @connections[key] && @connections[key].empty?
        @connections.delete(key)
        Rails.logger.info "🔌 SSE stream closed: #{key}"
      end
    end
  end

  def broadcast_to_stream(stream_type, event, payload)
    @mutex.synchronize do
      matching_keys = @connections.keys.select { |key| key_matches_stream?(key, stream_type) }

      matching_keys.each do |key|
        broadcast_to_connections(@connections[key], event, payload)
      end

      Rails.logger.debug { "📡 Broadcasted #{event} to #{stream_type} (#{matching_keys.size} streams)" }
    end
  end

  def broadcast_to_user(user_id, event, payload)
    @mutex.synchronize do
      user_keys = @connections.keys.select { |key| key.include?("user_#{user_id}") }

      user_keys.each do |key|
        broadcast_to_connections(@connections[key], event, payload)
      end

      Rails.logger.debug { "📡 Broadcasted #{event} to user #{user_id} (#{user_keys.size} streams)" }
    end
  end

  def broadcast_to_hashtag(hashtag, event, payload, local_only: false)
    stream_suffix = local_only ? ':local' : ''
    broadcast_to_stream("hashtag:#{hashtag.downcase}#{stream_suffix}", event, payload)
  end

  def broadcast_to_list(list_id, event, payload)
    broadcast_to_stream("list:#{list_id}", event, payload)
  end

  def active_connections_count
    @mutex.synchronize do
      @connections.values.sum(&:size)
    end
  end

  def streams_summary
    @mutex.synchronize do
      @connections.transform_values(&:size)
    end
  end

  private

  def connection_key(user_id, stream_type)
    case stream_type
    when 'user'
      "user_#{user_id}"
    when 'public'
      'public'
    when 'public:local'
      'public:local'
    when /\Ahashtag:(.+?)(?::local)?\z/
      hashtag = ::Regexp.last_match(1)
      local_suffix = stream_type.end_with?(':local') ? ':local' : ''
      "hashtag:#{hashtag.downcase}#{local_suffix}"
    when /\Alist:(\d+)\z/
      "list:#{::Regexp.last_match(1)}_user_#{user_id}"
    else
      "unknown:#{stream_type}_user_#{user_id}"
    end
  end

  def key_matches_stream?(key, stream_type)
    case stream_type
    when 'public'
      key == 'public'
    when 'public:local'
      key == 'public:local'
    when /\Ahashtag:(.+?)(?::local)?\z/
      hashtag = ::Regexp.last_match(1).downcase
      local_suffix = stream_type.end_with?(':local') ? ':local' : ''
      key == "hashtag:#{hashtag}#{local_suffix}"
    when /\Alist:(\d+)\z/
      key.start_with?("list:#{::Regexp.last_match(1)}_")
    when 'user'
      key.start_with?('user_')
    else
      false
    end
  end

  def broadcast_to_connections(connections, event, payload)
    return if connections.blank?

    connections.dup.each do |connection|
      connection.send_event(event, payload)
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      # 切断された接続を削除
      connections.delete(connection)
      Rails.logger.debug '🔌 Removed disconnected SSE connection'
    rescue StandardError => e
      Rails.logger.error "❌ SSE broadcast error: #{e.class}: #{e.message}"
      connections.delete(connection)
    end
  end
end
