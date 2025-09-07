# frozen_string_literal: true

# Webプッシュ通知の配信処理を専門的に扱うDelivery
# 通知タイプ別のペイロード構築と配信ロジックを分離
class WebPushDelivery
  def self.deliver_to_actor(actor, notification_type, title, body, options = {})
    return unless actor&.web_push_subscriptions&.any?

    actor.web_push_subscriptions.active.find_each do |subscription|
      next unless subscription.should_send_alert?(notification_type)

      SendWebPushNotificationJob.perform_later(subscription.id, notification_type, title, body, options)
    end
  end

  def self.deliver_to_subscription(subscription, notification_type, title, body, options = {})
    return false unless vapid_keys_configured?

    payload = subscription.push_payload(notification_type, title, body, options)
    send_push_notification(subscription, payload)
  end

  # 通知タイプ別の配信メソッド
  def self.deliver_follow_notification(follower, target, notification_id = nil)
    return unless target.local?

    deliver_to_actor(
      target,
      'follow',
      "#{follower.display_name_or_username}さんがあなたをフォローしました",
      follower.note.present? ? strip_tags(follower.note) : '',
      build_notification_options(notification_id, "@#{follower.username}", follower.avatar_url)
    )
  end

  def self.deliver_mention_notification(status, mentioned_actor, notification_id = nil)
    return unless mentioned_actor.local?

    deliver_to_actor(
      mentioned_actor,
      'mention',
      "#{status.actor.display_name_or_username}さんからメンション",
      strip_tags(status.content || ''),
      build_notification_options(notification_id, status.ap_id, status.actor.avatar_url)
    )
  end

  def self.deliver_favourite_notification(favourite, notification_id = nil)
    return unless favourite.object.actor.local?

    deliver_to_actor(
      favourite.object.actor,
      'favourite',
      "#{favourite.actor.display_name_or_username}さんがいいねしました",
      strip_tags(favourite.object.content || ''),
      build_notification_options(notification_id, favourite.object.ap_id, favourite.actor.avatar_url)
    )
  end

  def self.deliver_reblog_notification(reblog, notification_id = nil)
    return unless reblog.object.actor.local?

    deliver_to_actor(
      reblog.object.actor,
      'reblog',
      "#{reblog.actor.display_name_or_username}さんがリブログしました",
      strip_tags(reblog.object.content || ''),
      build_notification_options(notification_id, reblog.object.ap_id, reblog.actor.avatar_url)
    )
  end

  def self.deliver_follow_request_notification(follower, target, notification_id = nil)
    return unless target.local?

    deliver_to_actor(
      target,
      'follow_request',
      "#{follower.display_name_or_username}さんからフォローリクエスト",
      follower.note.present? ? strip_tags(follower.note) : '',
      build_notification_options(notification_id, "@#{follower.username}", follower.avatar_url)
    )
  end

  def self.deliver_poll_notification(status, account, notification_id = nil)
    return unless account.local?

    deliver_to_actor(
      account,
      'poll',
      '投票が終了しました',
      strip_tags(status.content || ''),
      build_notification_options(notification_id, status.ap_id, status.actor.avatar_url)
    )
  end

  def self.deliver_status_notification(status, account, notification_id = nil)
    return unless account.local?

    deliver_to_actor(
      account,
      'status',
      "#{status.actor.display_name_or_username}さんが投稿しました",
      strip_tags(status.content || ''),
      build_notification_options(notification_id, status.ap_id, status.actor.avatar_url)
    )
  end

  def self.deliver_update_notification(status, account, notification_id = nil)
    return unless account.local?

    deliver_to_actor(
      account,
      'update',
      "#{status.actor.display_name_or_username}さんが投稿を編集しました",
      strip_tags(status.content || ''),
      build_notification_options(notification_id, status.ap_id, status.actor.avatar_url)
    )
  end

  def self.deliver_quote_notification(quote_post, notification_id = nil)
    return unless quote_post.quoted_object.actor.local?

    deliver_to_actor(
      quote_post.quoted_object.actor,
      'quote',
      "#{quote_post.actor.display_name_or_username}さんがあなたの投稿を引用しました",
      strip_tags(quote_post.object.content || ''),
      build_notification_options(notification_id, quote_post.object.ap_id, quote_post.actor.avatar_url)
    )
  end

  class << self
    private

    # 通知オプションの構築
    def build_notification_options(notification_id, url_path, icon_url)
      {
        notification_id: notification_id,
        url: build_notification_url(url_path),
        icon: icon_url
      }
    end

    # 通知URLの構築
    def build_notification_url(path)
      if path.start_with?('@')
        "#{Rails.application.config.activitypub.base_url}/#{path}"
      else
        path
      end
    end

    # VAPID設定の確認
    def vapid_keys_configured?
      unless vapid_public_key.present? && vapid_private_key.present?
        Rails.logger.warn '⚠️ VAPID keys not configured, skipping push notification'
        return false
      end
      true
    end

    # プッシュ通知の送信
    def send_push_notification(subscription, payload)
      Rails.logger.info "🔐 Validating WebPush keys for #{subscription.actor.username}"

      unless valid_webpush_keys?(subscription)
        Rails.logger.warn "🔐 Invalid WebPush keys for #{subscription.actor.username}, skipping notification"
        Rails.logger.info "🧹 Removing invalid WebPush subscription for #{subscription.actor.username}"
        subscription.destroy
        return false
      end

      Rails.logger.info "✅ WebPush keys validated for #{subscription.actor.username}, sending notification"

      # Mastodon式の直接暗号化
      encrypted_payload = Webpush::Encryption.encrypt(payload.to_json, subscription.p256dh_key, subscription.auth_key)
      vapid_headers = build_vapid_headers(subscription.endpoint)

      send_encrypted_notification(subscription, encrypted_payload, vapid_headers)
      true
    rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription => e
      handle_invalid_subscription(subscription, e)
    rescue ArgumentError, OpenSSL::PKey::ECError => e
      Rails.logger.error "🔐 Encryption error for #{subscription.actor.username}: #{e.message}"
      false
    rescue StandardError => e
      handle_push_error(subscription, e)
    end

    # プッシュオプションの構築
    def build_push_options(subscription, payload = nil, validation_mode: false)
      options = {
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: build_vapid_options,
        ttl: 3600 * 24,
        urgency: 'normal'
      }

      options[:message] = payload.to_json unless validation_mode
      options
    end

    # VAPIDオプションの構築
    def build_vapid_options
      {
        subject: Rails.application.config.activitypub.base_url,
        public_key: vapid_public_key,
        private_key: vapid_private_key
      }
    end

    # 無効なサブスクリプションの処理
    def handle_invalid_subscription(subscription, error)
      Rails.logger.warn "📱 Invalid push subscription for #{subscription.actor.username}: #{error.message}"
      subscription.destroy
      false
    end

    # プッシュエラーの処理
    def handle_push_error(subscription, error)
      Rails.logger.error "❌ Push notification failed for #{subscription.actor.username}: #{error.message}"
      Rails.logger.error error.backtrace.join("\n") if Rails.env.development?
      false
    end

    # HTMLタグの除去
    def strip_tags(html)
      return '' if html.blank?

      ActionView::Base.full_sanitizer.sanitize(html).strip.truncate(100)
    end

    # VAPID公開キー
    def vapid_public_key
      ENV['VAPID_PUBLIC_KEY'] || Rails.application.credentials.dig(:vapid, :public_key)
    end

    # VAPID秘密キー
    def vapid_private_key
      ENV['VAPID_PRIVATE_KEY'] || Rails.application.credentials.dig(:vapid, :private_key)
    end

    # WebPush暗号化キーの適切な検証
    def valid_webpush_keys?(subscription)
      return false if subscription.p256dh_key.blank? || subscription.auth_key.blank?
      return false unless vapid_keys_configured?

      perform_webpush_validation(subscription)
    end

    # WebPush検証の実行
    def perform_webpush_validation(subscription)
      Rails.logger.info "🔍 Validating WebPush with endpoint: #{subscription.endpoint}"
      Webpush::Encryption.encrypt('validation_test', subscription.p256dh_key, subscription.auth_key)
      true
    rescue ArgumentError, OpenSSL::PKey::ECError, OpenSSL::PKey::EC::Point::Error => e
      Rails.logger.info "🔐 WebPush key validation failed (crypto): #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.info "🔐 Unexpected validation error: #{e.message}"
      false
    end

    # VAPID認証ヘッダーの構築
    def build_vapid_headers(endpoint)
      audience = URI.parse(endpoint).then { |uri| "#{uri.scheme}://#{uri.host}" }
      vapid_key = Webpush::VapidKey.from_keys(vapid_public_key, vapid_private_key)

      token = JWT.encode(
        {
          aud: audience,
          exp: 24.hours.from_now.to_i,
          sub: "mailto:#{Rails.application.config.activitypub.contact_email || 'admin@example.com'}"
        },
        vapid_key.curve,
        'ES256',
        typ: 'JWT'
      )

      {
        'Authorization' => "vapid t=#{token},k=#{vapid_key.public_key_for_push_header}",
        'Crypto-Key' => "p256ecdsa=#{vapid_key.public_key_for_push_header}"
      }
    end

    # 暗号化済み通知の送信
    def send_encrypted_notification(subscription, encrypted_payload, headers)
      require 'net/http'

      uri = URI.parse(subscription.endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/octet-stream'
      request['Content-Encoding'] = 'aes128gcm'
      request['TTL'] = '86400'
      request['Urgency'] = 'normal'
      headers.each { |key, value| request[key] = value }
      request.body = encrypted_payload

      response = http.request(request)

      if (400..499).cover?(response.code.to_i) && [408, 429].exclude?(response.code.to_i)
        Rails.logger.warn "📱 Invalid push subscription: #{response.code}"
        subscription.destroy
      elsif !(200...300).cover?(response.code.to_i)
        raise "HTTP #{response.code}: #{response.message}"
      end
    end
  end
end
