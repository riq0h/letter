# frozen_string_literal: true

module NotificationCreation
  extend ActiveSupport::Concern

  private

  def create_notification_for_mention
    create_notification_if_needed('mention') do
      Notification.create_mention_notification(self, object)
    end
  end

  def create_notification_for_favourite
    create_notification_if_needed('favourite') do
      Notification.create_favourite_notification(self, object)
    end
  end

  def create_notification_for_reblog
    create_notification_if_needed('reblog') do
      Notification.create_reblog_notification(self, object)
    end
  end

  def create_notification_if_needed(notification_type)
    return unless should_create_notification?

    return if notification_already_exists?(notification_type)

    yield
  rescue StandardError => e
    Rails.logger.error "Failed to create #{notification_type} notification: #{e.message}"
  end

  def should_create_notification?
    # 通知の受信者がローカルユーザの場合のみ作成する。
    # リモートユーザ宛の通知はどのクライアントからも読まれず、
    # DB書き込み・プッシュ判定・ストリーミング配信が全て無駄になる
    return false unless target_actor&.local?

    # 自分への言及、自分の投稿への自分のアクションは通知しない
    actor != object.actor
  end

  def target_actor
    case self.class.name
    when 'Mention'
      actor # メンションされた人
    when 'Favourite', 'Reblog'
      object.actor  # 投稿の作者
    end
  end

  def from_actor
    case self.class.name
    when 'Mention'
      object.actor  # 投稿者
    when 'Favourite', 'Reblog'
      actor # いいね/リツイートした人
    end
  end

  def notification_already_exists?(notification_type)
    Notification.exists?(
      account: target_actor,
      from_account: from_actor,
      activity_type: 'ActivityPubObject',
      activity_id: object.id.to_s,
      notification_type: notification_type
    )
  end
end
