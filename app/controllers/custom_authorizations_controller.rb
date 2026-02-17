# frozen_string_literal: true

class CustomAuthorizationsController < Doorkeeper::AuthorizationsController
  private

  # 既存トークンが存在しても常に認証画面を表示する
  def matching_token?
    false
  end
end
