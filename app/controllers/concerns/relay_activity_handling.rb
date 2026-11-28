# frozen_string_literal: true

# 購読しているリレー自身が送ってくる活動(購読の承認・拒否と、投稿の中継)の扱い。共有inboxと
# 個人のinboxのどちらに届いても同じに扱う。
# リレーが他人の活動をそのまま中継してきたもの(署名はリレー、actorは別人)は、転送と同じく
# ForwardedActivityHandlingで扱う(ActivityPubVerification#verify_signature)
module RelayActivityHandling
  extend ActiveSupport::Concern

  private

  # 送り主が、購読している(承認待ちを含む)リレーならそのリレー
  def sending_relay
    return @sending_relay if defined?(@sending_relay)

    actor_uri = ActivityPubOrigin.value_or_id(@activity['actor'])
    @sending_relay = Relay.where(state: %w[accepted pending]).find { |relay| relay.actor_uri == actor_uri }
  end

  def handle_relay_activity
    case @activity['type']
    when 'Accept' then handle_relay_accept
    when 'Reject' then handle_relay_reject
    when 'Announce' then handle_relay_announce
    else
      Rails.logger.info "🔀 Ignored #{@activity['type']} from relay #{sending_relay.domain}"
    end

    head :accepted
  end

  def handle_relay_accept
    return unless answers_relay_follow?

    sending_relay.update!(state: 'accepted', last_error: nil)
    Rails.logger.info "✅ Relay follow accepted: #{sending_relay.inbox_url}"
  end

  def handle_relay_reject
    return unless answers_relay_follow?

    sending_relay.update!(state: 'rejected', last_error: 'Follow request rejected by relay',
                          follow_activity_id: nil, followed_at: nil)
    Rails.logger.info "❌ Relay follow rejected: #{sending_relay.inbox_url}"
  end

  # こちらの購読の申し込み(Follow)への応答か。リレーは申し込みを丸ごと埋め込んで返すことが多い
  def answers_relay_follow?
    ActivityPubOrigin.value_or_id(@activity['object']) == sending_relay.follow_activity_id
  end

  # リレーが投稿を中継してきた。本文はリレーの署名しか無く作者本人のものと確かめられないので、
  # 元のサーバから取り直して取り込む
  def handle_relay_announce
    # 申し込みへの応答を取りこぼしていても、中継が届くなら購読は成り立っている
    sending_relay.update!(state: 'accepted', last_error: nil) if sending_relay.pending?

    object_uri = ActivityPubOrigin.value_or_id(@activity['object'])
    return if object_uri.blank? || ActivityPubObject.exists?(ap_id: object_uri)

    FetchForwardedObjectJob.perform_later(object_uri, nil, sending_relay.id)
  end
end
