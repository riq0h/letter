# frozen_string_literal: true

class SendActivityJob < ApplicationJob
  include ActivityPubObjectBuilding

  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  # 同時に配送するinbox数。応答しないサーバの待ち時間で全体が直列に積み上がらないよう並列化する
  # (以前は直列で、180宛先への配送に平均2.5分かかっていた)
  DELIVERY_CONCURRENCY = 8

  # Activity配信ジョブ
  # @param activity_id [String] 送信するActivityのID
  # @param target_inboxes [Array<String>] 配信先Inbox URLの配列
  def perform(activity_id, target_inboxes)
    @activity = Activity.find(activity_id)
    # 配送内容は宛先によらず同じなので1回だけ組み立てる
    @activity_data = build_activity_data(@activity)
    # 配送に失敗し続けているサーバ(件数は少ない)。宛先ごとに引かないよう先に読んでおく
    @failing_servers = UnavailableServer.all.index_by(&:domain)

    deliver_concurrently(Array(target_inboxes).uniq)

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

  def deliver_concurrently(inboxes)
    queue = Queue.new
    inboxes.each { |inbox| queue << inbox }
    queue.close

    workers = Array.new([DELIVERY_CONCURRENCY, inboxes.size].min) do
      Thread.new do
        Rails.application.executor.wrap do
          while (inbox_url = queue.pop)
            send_to_inbox(inbox_url)
          end
        end
      end
    end
    # 待機中に配送スレッド側のオートロードを妨げない
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { workers.each(&:join) }
  end

  def send_to_inbox(inbox_url)
    domain = inbox_domain(inbox_url)
    if @failing_servers[domain]&.unavailable?
      Rails.logger.info "⏭️ Skipping delivery to unavailable server: #{domain}"
      return false
    end

    result = ActivitySender.new.send_activity(
      activity: @activity_data,
      target_inbox: inbox_url,
      signing_actor: @activity.actor
    )

    track_delivery(domain, result)
    result[:success]
  rescue StandardError => e
    Rails.logger.error "💥 Failed to send to #{inbox_url}: #{e.message}"
    false
  end

  def build_activity_data(activity)
    case activity.activity_type
    when 'Create'
      if vote_activity?(activity)
        ActivityBuilders::VoteActivityBuilder.new(activity).build
      else
        ActivityBuilders::CreateActivityBuilder.new(activity).build
      end
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

  def inbox_domain(inbox_url)
    UnavailableServer.normalize_domain_name(URI(inbox_url.to_s).host)
  rescue URI::InvalidURIError
    nil
  end

  # 配送の成否をサーバごとに記録する。失敗が続いたサーバだけが配送停止になり、成功すれば再開する
  def track_delivery(domain, result)
    return if domain.blank?

    if UnavailableServer.delivery_failure?(result)
      UnavailableServer.record_failure(domain, result[:error])
    elsif @failing_servers.key?(domain)
      UnavailableServer.record_success(domain)
    end
  rescue StandardError => e
    Rails.logger.warn "⚠️ Failed to record delivery result for #{domain}: #{e.message}"
  end

  # Voteアクティビティかどうかを判定
  def vote_activity?(activity)
    return false if activity.raw_data.blank?

    parsed = JSON.parse(activity.raw_data)
    parsed.key?('vote_choice')
  rescue JSON::ParserError
    false
  end
end
