# frozen_string_literal: true

class SendActivityJob < ApplicationJob
  include ActivityPubObjectBuilding

  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  # Activity配信ジョブ
  # @param activity_id [String] 送信するActivityのID
  # @param target_inboxes [Array<String>] 配信先Inbox URLの配列
  def perform(activity_id, target_inboxes)
    @activity = Activity.find(activity_id)

    target_inboxes.each do |inbox_url|
      send_to_inbox(inbox_url)
    end

    @activity.update!(
      delivered: true,
      delivered_at: Time.current,
      delivery_attempts: @activity.delivery_attempts + 1
    )
  rescue StandardError => e
    Rails.logger.error "💥 SendActivityJob error for activity #{activity_id}: #{e.message}"
    @activity&.update(
      delivery_attempts: (@activity.delivery_attempts || 0) + 1,
      last_delivery_error: "#{e.class}: #{e.message}"
    )
    raise # Active Job のretry_onに委譲
  end

  private

  def send_to_inbox(inbox_url)
    # 配信前に利用不可能なサーバをチェック
    return skip_unavailable_server(inbox_url) if server_unavailable?(inbox_url)

    activity_data = build_activity_data(@activity)
    sender = ActivitySender.new

    result = sender.send_activity(
      activity: activity_data,
      target_inbox: inbox_url,
      signing_actor: @activity.actor
    )

    # 410応答の特別処理
    handle_delivery_result(result, inbox_url)
  rescue StandardError => e
    Rails.logger.error "💥 Failed to send to #{inbox_url}: #{e.message}"
    false
  end

  def build_activity_data(activity)
    case activity.activity_type
    when 'Create'
      ActivityBuilders::CreateActivityBuilder.new(activity).build
    when 'Announce'
      ActivityBuilders::AnnounceActivityBuilder.new(activity).build
    when 'Update'
      build_update_activity_data(activity)
    else
      ActivityBuilders::SimpleActivityBuilder.new(activity).build
    end
  end

  def build_update_activity_data(activity)
    unless activity.object
      Rails.logger.warn "⚠️ Update activity #{activity.id} has no object"
      return ActivityBuilders::SimpleActivityBuilder.new(activity).build
    end

    {
      '@context' => Rails.application.config.activitypub.context_url,
      'id' => activity.ap_id,
      'type' => 'Update',
      'actor' => activity.actor.ap_id,
      'published' => activity.published_at.iso8601,
      'object' => activity.object.to_activitypub,
      'to' => build_activity_audience(activity.object, :to),
      'cc' => build_activity_audience(activity.object, :cc)
    }
  end

  # 利用不可能なサーバかチェック
  def server_unavailable?(inbox_url)
    return false unless inbox_url

    begin
      domain = URI(inbox_url).host
      UnavailableServer.unavailable?(domain)
    rescue URI::InvalidURIError
      false
    end
  end

  # 利用不可能なサーバへの配信をスキップ
  def skip_unavailable_server(inbox_url)
    domain = URI(inbox_url).host
    Rails.logger.info "⏭️ Skipping delivery to unavailable server: #{domain}"
    false
  rescue URI::InvalidURIError
    Rails.logger.error "🔗 Invalid inbox URI: #{inbox_url}"
    false
  end

  # 配信結果の処理
  def handle_delivery_result(result, inbox_url)
    success = result[:success]

    # 410応答でドメインが利用不可能にマークされた場合の特別処理
    Rails.logger.warn "🚫 Domain marked unavailable due to 410 response: #{inbox_url}" if result[:code] == 410 && result[:domain_marked_unavailable]

    success
  end
end
