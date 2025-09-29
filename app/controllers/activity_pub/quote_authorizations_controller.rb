# frozen_string_literal: true

module ActivityPub
  class QuoteAuthorizationsController < ApplicationController
    before_action :set_quote_authorization, only: [:show]

    def show
      return head :not_found unless @quote_authorization

      respond_to do |format|
        format.json { render json: @quote_authorization.to_activitypub }
        format.html { redirect_to @quote_authorization.quote_post.object }
      end
    end

    private

    def set_quote_authorization
      # URLパラメータからIDを抽出（/quote_auth/:id の形式）
      auth_url = "#{Rails.application.config.activitypub.base_url}/quote_auth/#{params[:id]}"
      @quote_authorization = QuoteAuthorization.find_by(ap_id: auth_url)
    end
  end
end
