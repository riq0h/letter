# frozen_string_literal: true

module Api
  module Web
    # 送信先(中継サーバなど)が「この購読にはもう届かない」と判断したときに呼ぶ解除口(Mastodonと同じ)。
    # 送信時に付けた解除用URL(Unsubscribe-URL)の署名付きトークンだけで購読を特定する
    class PushSubscriptionsController < ActionController::API
      def destroy
        subscription = WebPushSubscription.find_by_token_for(:unsubscribe, params[:id])
        if subscription
          Rails.logger.info "🧹 Removing WebPush subscription #{subscription.id} at the push service's request"
          subscription.destroy
        end

        head :ok
      end
    end
  end
end
