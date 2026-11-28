# frozen_string_literal: true

# ストリーミングで配信する出来事。起きた場所で記録し、接続を持つPumaの各プロセスが読み取って配る
# (Streaming::Hub)。記録するのは対象のIDだけで、内容は配るときに受け取る人ごとに組み立てる。
# 誰も接続していないときは記録しない
class StreamingEvent < CacheRecord
  KINDS = %w[home status status.update delete notification conversation].freeze

  # 配り終えた出来事は残しておく必要がない。接続が切れて読み直すことはないので、少し余裕を見て消す
  RETENTION = 10.minutes

  validates :kind, inclusion: { in: KINDS }
  validates :target_id, presence: true

  scope :after, ->(id) { where('id > ?', id).order(:id) }

  class << self
    # ホームに投稿かブーストが加わった。target_idはホームでの並び順のID(sort_id)
    def publish_home(sort_id, recipient_id)
      publish('home', sort_id, recipient_id: recipient_id) if Streaming::Listeners.listening?(recipient_id)
    end

    # 公開・ハッシュタグ・リストのタイムラインに載りうる投稿が作られた
    def publish_status(object)
      publish('status', object.id) if Streaming::Listeners.timelines_listening?
    end

    def publish_status_update(object)
      publish('status.update', object.id) if Streaming::Listeners.listening?
    end

    # 投稿かブーストが消えた。消えたあとは公開範囲を調べられないので、公開の投稿だったかを残す
    def publish_delete(status_id, public_visibility:)
      publish('delete', status_id, public_visibility: public_visibility) if Streaming::Listeners.listening?
    end

    def publish_notification(notification)
      return unless Streaming::Listeners.listening?(notification.account_id)

      publish('notification', notification.id, recipient_id: notification.account_id)
    end

    def publish_conversation(conversation, recipient_ids)
      recipient_ids.each do |recipient_id|
        next unless Streaming::Listeners.listening?(recipient_id)

        publish('conversation', conversation.id, recipient_id: recipient_id)
      end
    end

    def trim
      where(created_at: ...RETENTION.ago).delete_all
    end

    private

    # 記録は今のトランザクションがすべて確定してから行う。確定前に配ると、配る側からは
    # まだ対象が見えない(取り消されれば存在しない)
    def publish(kind, target_id, recipient_id: nil, public_visibility: false)
      ActiveRecord.after_all_transactions_commit do
        create!(kind: kind, target_id: target_id.to_s, recipient_id: recipient_id,
                public_visibility: public_visibility, created_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn "📡 Failed to record streaming event #{kind} #{target_id}: #{e.message}"
      end
    rescue StandardError => e
      Rails.logger.warn "📡 Failed to record streaming event #{kind} #{target_id}: #{e.message}"
    end
  end
end
