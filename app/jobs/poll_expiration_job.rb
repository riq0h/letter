# frozen_string_literal: true

class PollExpirationJob < ApplicationJob
  include HTTParty

  queue_as :default

  def perform
    Rails.logger.info '🗳️  Checking for expired polls...'

    # 既に通知済みの投票IDを取得
    processed_poll_ids = Notification.where(notification_type: 'poll')
                                     .joins('JOIN polls ON polls.object_id = notifications.activity_id')
                                     .where(polls: { expires_at: ..Time.current })
                                     .pluck('polls.id')

    # 期限切れになった投票を取得（まだ処理されていないもの）
    expired_polls = Poll.where(expires_at: ..Time.current)
                        .joins(:object)
                        .where.not(id: processed_poll_ids)

    expired_polls.find_each do |poll|
      process_expired_poll(poll)
    end

    Rails.logger.info "🗳️  Processed #{expired_polls.count} expired polls"

    # 次回のPollExpirationJobをスケジュール
    schedule_next_execution
  end

  private

  def process_expired_poll(poll)
    # 外部pollの場合は最新結果を取得
    fetch_remote_poll_results(poll) unless poll.object.actor.local?

    # 投票の最終結果を計算
    if poll.object.actor.local?
      # ローカルpollの場合はローカル投票から計算
      poll.votes_count = poll.poll_votes.count
      poll.voters_count = poll.poll_votes.distinct.count(:actor_id)
      poll.save!(validate: false)
    end

    # ローカルユーザに通知（外部pollでも通知）
    notify_local_users_about_poll_results(poll)
  rescue StandardError => e
    Rails.logger.error "🗳️  Failed to process expired poll #{poll.id}: #{e.message}"
  end

  def fetch_remote_poll_results(poll)
    response = HTTParty.get(poll.object.ap_id, {
                              headers: activitypub_headers,
                              timeout: 10
                            })

    if response.success?
      update_poll_from_remote_data(poll, response.parsed_response)
    else
      Rails.logger.warn "🗳️  Failed to fetch remote poll results: HTTP #{response.code}"
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
        vote_counts = poll_options.map { |option| option['replies']['totalItems'] || 0 }

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

  def notify_local_users_about_poll_results(poll)
    # 投票に参加したローカルユーザに通知
    local_voters = poll.voters.where(local: true).distinct

    local_voters.find_each do |user|
      create_poll_notification(user, poll)
    end

    # ローカルユーザが作成したpollの場合も通知
    return unless poll.object.actor.local?

    creator = poll.object.actor
    return if local_voters.include?(creator)

    create_poll_notification(creator, poll)
  end

  def create_poll_notification(user, poll)
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

  def activitypub_headers
    {
      'Accept' => 'application/activity+json, application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
      'User-Agent' => 'letter/0.1 (ActivityPub)'
    }
  end

  def schedule_next_execution
    # 既にスケジュールされているPollExpirationJobがあるかチェック
    existing_scheduled = SolidQueue::Job
                         .where(class_name: 'PollExpirationJob')
                         .exists?(['scheduled_at > ?', Time.current])

    unless existing_scheduled
      # 10分後にPollExpirationJobを実行
      self.class.set(wait: 10.minutes).perform_later
      Rails.logger.debug { "🗳️  Next poll expiration job scheduled for #{10.minutes.from_now}" }
    end
  rescue StandardError => e
    Rails.logger.error "Failed to schedule next poll expiration job: #{e.message}"
  end
end
