# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    include ActionController::Helpers
    include Doorkeeper::Rails::Helpers
    include ErrorResponseHelper

    before_action :set_cache_headers

    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    protected

    def doorkeeper_unauthorized_render_options(*)
      { json: { error: 'This action requires authentication' } }
    end

    def doorkeeper_forbidden_render_options(*)
      { json: { error: 'This action is outside the authorized scopes' } }
    end

    def current_user
      return @current_user if defined?(@current_user)

      @current_user = Actor.find(doorkeeper_token.resource_owner_id) if doorkeeper_token
    rescue ActiveRecord::RecordNotFound
      @current_user = nil
    end

    def current_account
      current_user
    end

    def require_authenticated_user!
      render_authentication_required unless current_user
    end

    def require_user!
      if current_user && !current_user.local?
        render_local_only
      elsif !current_user
        render_authentication_required
      end
    end

    # 現在のリクエストが必要なOAuthスコープを持っているかチェック
    def doorkeeper_authorize!(*scopes)
      return false unless doorkeeper_token

      # トークンが必要なスコープを持っているかチェック
      if scopes.any?
        required_scopes = Doorkeeper::OAuth::Scopes.from_array(scopes)
        token_scopes = if doorkeeper_token.scopes.is_a?(Doorkeeper::OAuth::Scopes)
                         doorkeeper_token.scopes
                       else
                         Doorkeeper::OAuth::Scopes.from_string(doorkeeper_token.scopes)
                       end

        unless required_scopes.all? { |scope| token_scopes.include?(scope) }
          render json: {
            error: 'Insufficient scope',
            required_scopes: scopes
          }, status: :forbidden
          return false
        end
      end

      true
    end

    # 異なるトークン形式を処理するためDoorkeeperのトークンメソッドをオーバーライド
    def doorkeeper_token
      return @doorkeeper_token if defined?(@doorkeeper_token)

      @doorkeeper_token = find_access_token || nil
    end

    private

    def find_access_token
      # まずAuthorizationヘッダーを試行
      if request.authorization.present?
        token_from_authorization_header
      # 次にaccess_tokenパラメータを試行
      elsif params[:access_token].present?
        token_from_params
      end
    end

    def token_from_authorization_header
      auth_header = request.authorization
      return unless auth_header&.match(/^Bearer\s+(.+)$/i)

      token_value = ::Regexp.last_match(1)
      ::Doorkeeper::AccessToken.find_by(token: token_value)
    end

    def token_from_params
      ::Doorkeeper::AccessToken.find_by(token: params[:access_token])
    end

    def set_cache_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, max-age=0, must-revalidate'
    end

    def not_found
      render_not_found
    end

    def unprocessable_entity
      render_validation_failed
    end

    def too_many_requests
      render_rate_limited
    end
  end
end
