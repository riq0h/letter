# frozen_string_literal: true

class SSEConnection
  attr_reader :user, :stream_type, :created_at

  def initialize(response_stream, user, stream_type)
    @stream = response_stream
    @user = user
    @stream_type = stream_type
    @created_at = Time.current
    @last_event_id = 0
    @closed = false

    Rails.logger.debug { "🔗 SSE connection created for #{user.username}:#{stream_type}" }
  end

  def send_event(event, payload)
    return if @closed

    begin
      data = if payload.is_a?(String)
               payload
             else
               payload.to_json
             end

      @stream.write("event: #{event}\n")
      @stream.write("data: #{data}\n")
      @stream.write("id: #{generate_event_id}\n")
      @stream.write("\n")

      Rails.logger.debug { "📤 Sent #{event} to #{@user.username}:#{@stream_type}" }
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      Rails.logger.debug { "🔌 SSE connection closed during send: #{e.class}" }
      close
      raise
    end
  end

  def send_heartbeat
    return if @closed

    begin
      @stream.write(": heartbeat #{Time.current.to_i}\n\n")
      Rails.logger.debug { "💓 Heartbeat sent to #{@user.username}:#{@stream_type}" }
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET => e
      Rails.logger.debug { "🔌 SSE connection closed during heartbeat: #{e.class}" }
      close
      raise
    end
  end

  def send_welcome_message
    send_event('connected', {
                 stream: [@stream_type],
                 user: @user.username,
                 timestamp: Time.current.iso8601
               })
  end

  def close
    return if @closed

    begin
      @stream&.close
    rescue StandardError => e
      Rails.logger.debug { "Error closing SSE stream: #{e.message}" }
    ensure
      @closed = true
      SSEConnectionManager.instance.unregister_connection(@user.id, @stream_type, self)
      Rails.logger.info "🔌 SSE connection closed for #{@user.username}:#{@stream_type}"
    end
  end

  def closed?
    @closed
  end

  def connection_info
    {
      user: @user.username,
      stream_type: @stream_type,
      created_at: @created_at,
      duration: Time.current - @created_at,
      events_sent: @last_event_id
    }
  end

  private

  def generate_event_id
    @last_event_id += 1
    "#{@created_at.to_i}_#{@last_event_id}"
  end
end
