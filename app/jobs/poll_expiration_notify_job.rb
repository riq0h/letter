# frozen_string_literal: true

class PollExpirationNotifyJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(poll_id)
    @poll = Poll.find(poll_id)

    return if missing_expiration?

    if not_due_yet?
      requeue!
      return
    end

    # リモートPollの最新結果を取得
    fetch_remote_poll_results(@poll) unless @poll.object.actor.local?

    # ローカルPollの場合は投票数を計算
    update_local_poll_counts if @poll.object.actor.local?

    # 通知を送信
    notify_local_voters!
    notify_poll_owner! if @poll.object.actor.local?
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "🗳️  Poll #{poll_id} not found, skipping expiration notification"
    true
  rescue StandardError => e
    Rails.logger.error "🗳️  Failed to process expired poll #{poll_id}: #{e.message}"
    raise e
  end

  private

  def missing_expiration?
    @poll.expires_at.nil?
  end

  def not_due_yet?
    @poll.expires_at.present? && !@poll.expired?
  end

  def requeue!
    # まだ期限が来ていない場合は再スケジュール
    self.class.set(wait_until: @poll.expires_at + 5.minutes).perform_later(@poll.id)
    Rails.logger.debug { "🗳️  Poll #{@poll.id} not yet expired, rescheduled for #{@poll.expires_at + 5.minutes}" }
  end

  def fetch_remote_poll_results(poll)
    data = ActivityPubHttpClient.fetch_object(poll.object.ap_id)

    if data
      update_poll_from_remote_data(poll, data)
    else
      Rails.logger.warn "🗳️  Failed to fetch remote poll results for poll #{poll.id}"
    end
  rescue StandardError => e
    Rails.logger.error "🗳️  Failed to fetch remote poll results: #{e.message}"
  end

  def update_poll_from_remote_data(poll, data)
    return unless data.is_a?(Hash)

    # ActivityPubのQuestion/Pollオブジェクトからデータを抽出
    if data['oneOf'] || data['anyOf']
      poll_options = data['oneOf'] || data['anyOf']

      # 各選択肢の投票数を更新
      if poll_options.is_a?(Array)
        vote_counts = poll_options.map { |option| option.dig('replies', 'totalItems') || 0 }

        # pollのoptionsを投票数で更新
        updated_options = poll.options.each_with_index.map do |option, index|
          option.merge('votes_count' => vote_counts[index] || 0)
        end

        # コールバックをスキップしてリモートデータで更新
        votes_count_value = vote_counts.sum
        voters_count_value = data['votersCount'] || vote_counts.sum

        poll.update_columns(
          options: updated_options,
          votes_count: votes_count_value,
          voters_count: voters_count_value
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error "🗳️  Failed to parse remote poll data: #{e.message}"
  end

  def update_local_poll_counts
    @poll.votes_count = @poll.poll_votes.count
    @poll.voters_count = @poll.poll_votes.distinct.count(:actor_id)
    @poll.save!(validate: false)
  end

  def notify_local_voters!
    # 投票に参加したローカルユーザに通知
    local_voters = @poll.voters.where(local: true).distinct

    local_voters.find_each do |user|
      create_poll_notification(user, @poll)
    end
  end

  def notify_poll_owner!
    # Poll作成者に通知（既に投票者として通知されていない場合）
    creator = @poll.object.actor
    return if @poll.voters.where(local: true).exists?(id: creator.id)

    create_poll_notification(creator, @poll)
  end

  def create_poll_notification(user, poll)
    # 既に通知が存在する場合はスキップ
    return if Notification.exists?(
      account: user,
      notification_type: 'poll',
      activity_type: 'ActivityPubObject',
      activity_id: poll.object.id
    )

    Notification.create!(
      account: user,
      notification_type: 'poll',
      from_account: poll.object.actor,
      activity_type: 'ActivityPubObject',
      activity_id: poll.object.id
    )
  rescue StandardError => e
    Rails.logger.error "🗳️  Failed to create poll notification: #{e.message}"
    raise e
  end
end
