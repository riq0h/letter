# frozen_string_literal: true

class CustomAuthorizationsController < Doorkeeper::AuthorizationsController
  private

  # 既存トークンの有無に関わらず常に認証画面を表示する
  def render_success
    if Doorkeeper.configuration.api_only
      render json: pre_auth
    else
      render :new
    end
  end
end
