# frozen_string_literal: true

module Api
  module V1
    class AppsController < Api::BaseController
      before_action :doorkeeper_authorize!, only: [:verify_credentials]

      # POST /api/v1/apps
      # 新しいアプリケーションを登録
      def create
        @application = ::Doorkeeper::Application.new(application_params)

        if @application.save
          render json: serialized_application(@application), status: :created
        else
          render json: { error: 'Validation failed', details: @application.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # GET /api/v1/apps/verify_credentials
      # アプリケーション認証情報を検証
      def verify_credentials
        render json: serialized_application(doorkeeper_token.application)
      end

      private

      def application_params
        client_name = params[:client_name]
        redirect_uris = params[:redirect_uris]

        raise ActionController::ParameterMissing, 'client_name and redirect_uris are required' if client_name.blank? || redirect_uris.blank?

        {
          name: client_name,
          redirect_uri: redirect_uris,
          scopes: params[:scopes] || 'read',
          website: params[:website],
          confidential: false
        }
      end

      def serialized_application(application)
        {
          id: application.id.to_s,
          name: application.name,
          website: application.website,
          redirect_uri: application.redirect_uri,
          client_id: application.uid,
          client_secret: application.secret,
          vapid_key: vapid_public_key || 'not_configured'
        }
      end

      def vapid_public_key
        ENV['VAPID_PUBLIC_KEY'] || Rails.application.credentials.dig(:vapid, :public_key)
      end
    end
  end
end
