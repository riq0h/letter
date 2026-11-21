# frozen_string_literal: true

module ActivityPub
  class QuoteAuthorizationsController < ApplicationController
    before_action :set_quote_authorization, only: [:show]

    # 引用した側のサーバは、承認(Accept)のresultに示したこのURLを取得して承認を確かめる
    def show
      return head :not_found unless @quote_authorization
      return redirect_to(@quote_authorization.quote_post.object) unless activitypub_request? || request.format.json?

      render json: @quote_authorization.to_activitypub, content_type: 'application/activity+json; charset=utf-8'
    end

    private

    def set_quote_authorization
      # URLパラメータからIDを抽出（/quote_auth/:id の形式）
      auth_url = "#{Rails.application.config.activitypub.base_url}/quote_auth/#{params[:id]}"
      @quote_authorization = QuoteAuthorization.find_by(ap_id: auth_url)
    end
  end
end
