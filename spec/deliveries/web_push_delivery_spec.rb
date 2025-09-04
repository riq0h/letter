# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebPushDelivery do
  let(:actor) { create(:actor, local: true, note: '') }
  let(:remote_actor) { create(:actor, :remote, note: '') }
  let(:status) { create(:activity_pub_object, actor: remote_actor) }
  let(:subscription) { create(:web_push_subscription, :with_alerts, actor: actor) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('VAPID_PUBLIC_KEY').and_return('test_public_key')
    allow(ENV).to receive(:[]).with('VAPID_PRIVATE_KEY').and_return('test_private_key')
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '.deliver_to_actor' do
    context 'when actor has web push subscriptions' do
      before do
        actor.web_push_subscriptions << subscription
      end

      it 'queues notification jobs for active subscriptions' do
        allow(subscription).to receive(:should_send_alert?).and_return(true)
        expect(SendWebPushNotificationJob).to receive(:perform_later)

        described_class.deliver_to_actor(actor, 'mention', 'Test Title', 'Test Body')
      end

      it 'skips subscriptions that should not send alerts' do
        # デフォルトのアラート設定では、mentionはtrue、でもテストでは無効にする
        subscription.alerts = subscription.alerts.merge('mention' => false)
        subscription.save!
        expect(SendWebPushNotificationJob).not_to receive(:perform_later)

        described_class.deliver_to_actor(actor, 'mention', 'Test Title', 'Test Body')
      end
    end

    context 'when actor has no subscriptions' do
      it 'does not queue any jobs' do
        expect(SendWebPushNotificationJob).not_to receive(:perform_later)

        described_class.deliver_to_actor(actor, 'mention', 'Test Title', 'Test Body')
      end
    end

    context 'when actor is nil' do
      it 'returns early without error' do
        expect(SendWebPushNotificationJob).not_to receive(:perform_later)

        described_class.deliver_to_actor(nil, 'mention', 'Test Title', 'Test Body')
      end
    end
  end

  describe '.deliver_to_subscription' do
    let(:payload) { { 'title' => 'Test', 'body' => 'Body', 'data' => { 'url' => 'http://example.com' } } }
    let(:push_options) do
      {
        message: payload.to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: {
          subject: Rails.application.config.activitypub.base_url,
          public_key: 'test_public_key',
          private_key: 'test_private_key'
        },
        ttl: 3600 * 24,
        urgency: 'normal'
      }
    end

    before do
      allow(subscription).to receive(:push_payload).and_return(payload)
    end

    context 'when VAPID keys are configured' do
      it 'sends push notification with correct parameters' do
        # 事前検証を通す
        allow(described_class).to receive(:valid_webpush_keys?).and_return(true)
        expect(WebPush).to receive(:payload_send).with(push_options)

        result = described_class.deliver_to_subscription(subscription, 'mention', 'Test', 'Body')

        expect(result).to be true
      end

      it 'handles invalid subscription errors' do
        allow(described_class).to receive(:valid_webpush_keys?).and_return(true)
        allow(WebPush).to receive(:payload_send).and_raise(WebPush::InvalidSubscription, 'Invalid endpoint')

        result = described_class.deliver_to_subscription(subscription, 'mention', 'Test', 'Body')

        expect(result).to be false
      end

      it 'handles expired subscription errors' do
        allow(described_class).to receive(:valid_webpush_keys?).and_return(true)
        allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription, 'Subscription expired')

        result = described_class.deliver_to_subscription(subscription, 'mention', 'Test', 'Body')

        expect(result).to be false
      end

      it 'handles general errors without destroying subscription' do
        # 事前検証を通す
        allow(described_class).to receive(:valid_webpush_keys?).and_return(true)
        allow(WebPush).to receive(:payload_send).and_raise(StandardError, 'Network error')
        expect(subscription).not_to receive(:destroy)
        expect(Rails.logger).to receive(:error).with(/Push notification failed/)

        result = described_class.deliver_to_subscription(subscription, 'mention', 'Test', 'Body')

        expect(result).to be false
      end
    end

    context 'when VAPID keys are not configured' do
      before do
        allow(ENV).to receive(:[]).with('VAPID_PUBLIC_KEY').and_return(nil)
        allow(ENV).to receive(:[]).with('VAPID_PRIVATE_KEY').and_return(nil)
      end

      it 'returns false without sending notification' do
        expect(WebPush).not_to receive(:payload_send)

        result = described_class.deliver_to_subscription(subscription, 'mention', 'Test', 'Body')

        expect(result).to be false
      end
    end
  end

  describe 'notification type specific methods' do
    let(:local_status) { create(:activity_pub_object, actor: actor, content: 'Test content') }
    let(:favourite) { instance_double(Favourite, object: local_status, actor: remote_actor) }
    let(:reblog) { instance_double(Reblog, object: local_status, actor: remote_actor) }

    describe '.deliver_follow_notification' do
      it 'delivers follow notification to local actor with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'follow',
          String, # ランダム生成されるため動的にチェック
          '',
          hash_including(
            notification_id: nil,
            url: "#{Rails.application.config.activitypub.base_url}/@#{remote_actor.username}",
            icon: remote_actor.avatar_url
          )
        )

        described_class.deliver_follow_notification(remote_actor, actor)
      end

      it 'returns early for remote actor' do
        expect(described_class).not_to receive(:deliver_to_actor)

        described_class.deliver_follow_notification(remote_actor, remote_actor)
      end
    end

    describe '.deliver_mention_notification' do
      it 'delivers mention notification to local actor with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'mention',
          "#{local_status.actor.display_name_or_username}さんからメンション",
          'Test content',
          {
            notification_id: 123,
            url: local_status.ap_id,
            icon: local_status.actor.avatar_url
          }
        )

        described_class.deliver_mention_notification(local_status, actor, 123)
      end

      it 'returns early for remote actor' do
        expect(described_class).not_to receive(:deliver_to_actor)

        described_class.deliver_mention_notification(local_status, remote_actor)
      end
    end

    describe '.deliver_favourite_notification' do
      it 'delivers favourite notification to status owner with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'favourite',
          String,
          'Test content',
          hash_including(
            url: local_status.ap_id,
            icon: remote_actor.avatar_url
          )
        )

        described_class.deliver_favourite_notification(favourite, 456)
      end

      it 'returns early for remote status owner' do
        remote_status = create(:activity_pub_object, actor: remote_actor)
        remote_favourite = create(:favourite, actor: actor, object: remote_status)

        expect(described_class).not_to receive(:deliver_to_actor)

        described_class.deliver_favourite_notification(remote_favourite)
      end
    end

    describe '.deliver_reblog_notification' do
      it 'delivers reblog notification to status owner with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'reblog',
          String,
          'Test content',
          hash_including(
            url: local_status.ap_id,
            icon: remote_actor.avatar_url
          )
        )

        described_class.deliver_reblog_notification(reblog, 789)
      end

      it 'returns early for remote status owner' do
        remote_status = create(:activity_pub_object, actor: remote_actor)
        remote_reblog = create(:reblog, actor: actor, object: remote_status)

        expect(described_class).not_to receive(:deliver_to_actor)

        described_class.deliver_reblog_notification(remote_reblog)
      end
    end

    describe '.deliver_follow_request_notification' do
      it 'delivers follow request notification with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'follow_request',
          String,
          '',
          hash_including(
            notification_id: 101,
            url: "#{Rails.application.config.activitypub.base_url}/@#{remote_actor.username}",
            icon: remote_actor.avatar_url
          )
        )

        described_class.deliver_follow_request_notification(remote_actor, actor, 101)
      end
    end

    describe '.deliver_poll_notification' do
      it 'delivers poll notification with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'poll',
          '投票が終了しました',
          'Test content',
          {
            notification_id: 202,
            url: local_status.ap_id,
            icon: local_status.actor.avatar_url
          }
        )

        described_class.deliver_poll_notification(local_status, actor, 202)
      end
    end

    describe '.deliver_status_notification' do
      it 'delivers status notification with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'status',
          "#{local_status.actor.display_name_or_username}さんが投稿しました",
          'Test content',
          {
            notification_id: 303,
            url: local_status.ap_id,
            icon: local_status.actor.avatar_url
          }
        )

        described_class.deliver_status_notification(local_status, actor, 303)
      end
    end

    describe '.deliver_update_notification' do
      it 'delivers update notification with correct parameters' do
        expect(described_class).to receive(:deliver_to_actor).with(
          actor,
          'update',
          "#{local_status.actor.display_name_or_username}さんが投稿を編集しました",
          'Test content',
          {
            notification_id: 404,
            url: local_status.ap_id,
            icon: local_status.actor.avatar_url
          }
        )

        described_class.deliver_update_notification(local_status, actor, 404)
      end
    end
  end

  describe '.strip_tags' do
    it 'removes HTML tags from content' do
      html = '<p>Hello <strong>world</strong>!</p>'

      result = described_class.send(:strip_tags, html)

      expect(result).to eq('Hello world!')
    end

    it 'truncates long content' do
      long_text = 'a' * 200

      result = described_class.send(:strip_tags, long_text)

      expect(result.length).to eq(100)
    end

    it 'handles blank content' do
      expect(described_class.send(:strip_tags, '')).to eq('')
      expect(described_class.send(:strip_tags, nil)).to eq('')
    end
  end

  describe '.build_notification_options' do
    it 'builds proper notification options' do
      result = described_class.send(:build_notification_options, 123, '@user', 'icon.png')

      expect(result).to eq({
                             notification_id: 123,
                             url: "#{Rails.application.config.activitypub.base_url}/@user",
                             icon: 'icon.png'
                           })
    end

    it 'handles full URLs' do
      result = described_class.send(:build_notification_options, 123, 'https://example.com/status', 'icon.png')

      expect(result).to eq({
                             notification_id: 123,
                             url: 'https://example.com/status',
                             icon: 'icon.png'
                           })
    end
  end

  describe '.vapid_keys_configured?' do
    it 'returns true when both keys are present' do
      result = described_class.send(:vapid_keys_configured?)

      expect(result).to be true
    end

    it 'returns false when public key is missing' do
      allow(ENV).to receive(:[]).with('VAPID_PUBLIC_KEY').and_return(nil)

      result = described_class.send(:vapid_keys_configured?)

      expect(result).to be false
    end

    it 'returns false when private key is missing' do
      allow(ENV).to receive(:[]).with('VAPID_PRIVATE_KEY').and_return(nil)

      result = described_class.send(:vapid_keys_configured?)

      expect(result).to be false
    end
  end

  describe '.valid_webpush_keys?' do
    let(:valid_subscription) do
      create(:web_push_subscription,
             actor: actor,
             p256dh_key: valid_p256dh_key,
             auth_key: valid_auth_key)
    end

    let(:valid_p256dh_key) do
      # 有効な65バイト uncompressed NIST P-256 公開鍵
      key_bytes = "\u0004#{"\x01" * 32}#{"\x02" * 32}"
      Base64.strict_encode64(key_bytes)
    end

    let(:valid_auth_key) do
      # 有効な16バイト認証キー
      Base64.strict_encode64('a' * 16)
    end

    it 'returns true for valid keys' do
      allow(WebPush).to receive(:payload_send).and_return(true)

      expect(described_class.send(:valid_webpush_keys?, valid_subscription)).to be true
    end

    it 'returns false for blank keys' do
      blank_subscription = build(:web_push_subscription, p256dh_key: '', auth_key: '')
      expect(described_class.send(:valid_webpush_keys?, blank_subscription)).to be false
    end

    it 'returns false for invalid Base64' do
      invalid_subscription = build(:web_push_subscription,
                                   p256dh_key: 'invalid!@#',
                                   auth_key: 'invalid!@#')
      expect(described_class.send(:valid_webpush_keys?, invalid_subscription)).to be false
    end

    it 'returns false when encryption fails' do
      subscription = build(:web_push_subscription,
                           p256dh_key: Base64.strict_encode64('a' * 65),
                           auth_key: Base64.strict_encode64('b' * 16))
      allow(WebPush).to receive(:payload_send).and_raise(ArgumentError, 'Invalid key')

      expect(described_class.send(:valid_webpush_keys?, subscription)).to be false
    end
  end

  describe '.send_push_notification with key validation' do
    let(:payload) { { title: 'Test', body: 'Test body' } }

    it 'skips notification and logs warning when keys are invalid' do
      allow(described_class).to receive(:valid_webpush_keys?).and_return(false)
      expect(Rails.logger).to receive(:warn).with(/Invalid WebPush keys.*skipping notification/)
      expect(WebPush).not_to receive(:payload_send)

      result = described_class.send(:send_push_notification, subscription, payload)
      expect(result).to be false
    end

    it 'handles OpenSSL::PKey::ECError gracefully when keys are valid' do
      allow(described_class).to receive_messages(valid_webpush_keys?: true, build_push_options: {})
      allow(WebPush).to receive(:payload_send).and_raise(OpenSSL::PKey::ECError, 'EC_POINT_bn2point: invalid encoding')
      expect(Rails.logger).to receive(:error).with(/Unexpected encryption error/)

      result = described_class.send(:send_push_notification, subscription, payload)
      expect(result).to be false
    end
  end
end
