# frozen_string_literal: true

class ScheduledStatus < ApplicationRecord
  belongs_to :actor
  has_many_attached :media_attachments

  validates :scheduled_at, presence: true
  validates :params, presence: true
  validate :validate_scheduled_time
  validate :validate_params_format

  after_create :schedule_publish_job

  scope :due, -> { where(scheduled_at: ..Time.current) }
  scope :pending, -> { where('scheduled_at > ?', Time.current) }
  scope :for_actor, ->(actor) { where(actor: actor) }

  def self.process_due_statuses!
    due.find_each do |scheduled_status|
      scheduled_status.publish!
    rescue StandardError => e
      Rails.logger.error "Failed to publish scheduled status #{scheduled_status.id}: #{e.message}"
      # エラー時は削除せず再試行または手動処理に委ねる
    end
  end

  def publish!
    result = PublishScheduledStatusOrganizer.call(self)

    raise StandardError, result.error unless result.success?

    result.status
  end

  def due?
    scheduled_at <= Time.current
  end

  def pending?
    scheduled_at > Time.current
  end

  def to_mastodon_api
    {
      id: id.to_s,
      scheduled_at: scheduled_at.iso8601,
      params: serialize_params,
      media_attachments: serialize_media_attachments
    }
  end

  private

  def validate_scheduled_time
    return unless scheduled_at

    min_time = 5.minutes.from_now
    max_time = 2.years.from_now

    if scheduled_at < min_time
      errors.add(:scheduled_at, 'must be at least 5 minutes from now')
    elsif scheduled_at > max_time
      errors.add(:scheduled_at, 'cannot be more than 2 years from now')
    end
  end

  def validate_params_format
    return unless params

    unless params.is_a?(Hash)
      errors.add(:params, 'must be a hash')
      return
    end

    errors.add(:params, 'must include status text') if params['status'].blank?

    return unless params['status'].to_s.length > 9999

    errors.add(:params, 'status text too long (maximum 9999 characters)')
  end

  def serialize_params
    base_params = params.except('poll').merge(
      poll: params['poll'] ? serialize_poll_params : nil
    ).compact

    # statusフィールドが存在する場合、textフィールドとしても提供
    base_params['text'] = base_params['status'] if base_params['status'].present?

    # visibilityフィールドが必須のため、デフォルト値を確保
    base_params['visibility'] ||= 'public'

    base_params
  end

  def serialize_poll_params
    poll_params = params['poll']
    return nil unless poll_params

    {
      options: poll_params['options'],
      expires_in: poll_params['expires_in'],
      multiple: poll_params['multiple'] || false,
      hide_totals: poll_params['hide_totals'] || false
    }
  end

  def serialize_media_attachments
    return [] unless media_attachment_ids.is_a?(Array)

    MediaAttachment.where(id: media_attachment_ids, actor: actor).map do |attachment|
      {
        id: attachment.id.to_s,
        type: attachment.file_type,
        url: attachment.file_url,
        preview_url: attachment.preview_url,
        remote_url: nil,
        description: attachment.description,
        blurhash: attachment.blurhash
      }
    end
  end

  def schedule_publish_job
    PublishScheduledStatusJob.set(wait_until: scheduled_at).perform_later(id)
  end
end
