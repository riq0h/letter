# frozen_string_literal: true

class PollCreationService
  def self.create_for_status(status, poll_params)
    new(status, poll_params).create
  end

  def initialize(status, poll_params)
    @status = status
    @poll_params = poll_params
  end

  def create
    return nil unless valid_params?

    poll = @status.build_poll(
      options: formatted_options,
      expires_at: calculate_expiry,
      multiple: @poll_params[:multiple] || false,
      hide_totals: @poll_params[:hide_totals] || false,
      votes_count: 0,
      voters_count: 0
    )

    if poll.save
      Rails.logger.info "📊 Poll created with #{poll.options.count} options"
      schedule_expiration_job(poll)
      poll
    else
      Rails.logger.error "Failed to create poll: #{poll.errors.full_messages.join(', ')}"
      nil
    end
  end

  private

  def schedule_expiration_job(poll)
    PollExpirationNotifyJob.set(wait_until: poll.expires_at).perform_later(poll.id)
    Rails.logger.debug { "🗳️  Poll expiration job scheduled for #{poll.expires_at}" }
  rescue StandardError => e
    Rails.logger.error "Failed to schedule poll expiration job: #{e.message}"
  end

  def valid_params?
    return false if @poll_params.blank?
    return false unless @poll_params[:options].is_a?(Array)

    # 空でない選択肢をフィルタリング
    filtered_options = @poll_params[:options].compact_blank
    return false unless filtered_options.length.between?(2, 4)

    # フィルタリングされた選択肢を使用
    @poll_params[:options] = filtered_options
    true
  end

  def formatted_options
    @poll_params[:options].map do |option_text|
      { 'title' => option_text.to_s.strip.truncate(50) }
    end
  end

  def calculate_expiry
    expires_in = @poll_params[:expires_in].to_i

    # デフォルトは1日（86400秒）
    expires_in = 86_400 if expires_in.zero?

    # 最小5分、最大7日
    expires_in = expires_in.clamp(300, 604_800)

    Time.current + expires_in.seconds
  end
end
