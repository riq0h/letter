# frozen_string_literal: true

module Oauth
  class TokensController < Doorkeeper::TokensController
    # ログアウトでトークンを失効させるときは、そのトークンのプッシュ通知の購読も消す(Mastodonと同じ)
    def revoke
      WebPushSubscription.where(access_token_id: token.id).delete_all if token.present? && authorized? && token.accessible?

      super
    end
  end
end
