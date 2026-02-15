# frozen_string_literal: true

class SseConnectionManager
  include Singleton

  MAX_CONNECTIONS_PER_USER = 5
  STALE_CONNECTION_THRESHOLD = 24.hours

  def initialize
    @connections = {}
    @mutex = Mutex.new
    @last_cleanup = Time.current
  end

  def register_connection(user_id, stream_type, connection)
    @mutex.synchronize do
      key = connection_key(user_id, stream_type)
      @connections[key] ||= []

      # ユーザ毎の接続数制限: 最も古い接続を閉じる
      user_keys = @connections.keys.select { |k| k.include?("user_#{user_id}") }
      total_user_connections = user_keys.sum { |k| @connections[k]&.size || 0 }
      evict_oldest_connection(user_keys) if total_user_connections >= MAX_CONNECTIONS_PER_USER

      @connections[key] << connection
      Rails.logger.info "🔗 SSE connection registered: #{key} (total: #{@connections[key].size})"

      # 定期的にスタートコネクションをクリーンアップ
      cleanup_stale_connections_if_needed
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

  def evict_oldest_connection(user_keys)
    user_keys.each do |key|
      next if @connections[key].blank?

      oldest = @connections[key].shift
      begin
        oldest.close if oldest.respond_to?(:close)
      rescue StandardError
        nil
      end
      @connections.delete(key) if @connections[key].empty?
      Rails.logger.info "🔌 Evicted oldest SSE connection for: #{key}"
      break
    end
  end

  def cleanup_stale_connections_if_needed
    return if Time.current - @last_cleanup < 10.minutes

    @last_cleanup = Time.current
    stale_threshold = STALE_CONNECTION_THRESHOLD.ago

    @connections.each do |key, connections|
      connections.reject! do |conn|
        if conn.respond_to?(:created_at) && conn.created_at < stale_threshold
          begin
            conn.close if conn.respond_to?(:close)
          rescue StandardError
            nil
          end
          true
        else
          false
        end
      end
      @connections.delete(key) if connections.empty?
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
