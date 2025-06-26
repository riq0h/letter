# frozen_string_literal: true

module Api
  module V1
    module Push
      class SubscriptionController < Api::BaseController
        include ValidationErrorRendering

        before_action :doorkeeper_authorize!
        before_action :require_user!
        before_action :set_subscription, only: %i[show update destroy]

        # GET /api/v1/push/subscription
        def show
          if @subscription
            render json: serialized_subscription(@subscription)
          else
            render_not_found('Push subscription')
          end
        end

        # POST /api/v1/push/subscription
        def create
          subscription_params = extract_subscription_params

          return render_validation_error('Missing required subscription data') if subscription_params.nil?

          @subscription = current_account.web_push_subscriptions.find_or_initialize_by(
            endpoint: subscription_params[:endpoint]
          )

          @subscription.assign_attributes(
            p256dh_key: subscription_params[:keys][:p256dh],
            auth_key: subscription_params[:keys][:auth],
            data: {
              alerts: extract_alerts,
              policy: params.dig(:data, :policy) || 'all'
            }.to_json
          )

          if @subscription.save
            render json: serialized_subscription(@subscription), status: :created
          else
            render json: {
              error: 'Validation failed',
              details: @subscription.errors.full_messages
            }, status: :unprocessable_entity
          end
        end

        # PUT /api/v1/push/subscription
        def update
          if @subscription
            current_data = @subscription.data_hash
            current_data['alerts'] = extract_alerts
            current_data['policy'] = params.dig(:data, :policy) if params.dig(:data, :policy).present?
            @subscription.data_hash = current_data

            if @subscription.save
              render json: serialized_subscription(@subscription)
            else
              render json: {
                error: 'Validation failed',
                details: @subscription.errors.full_messages
              }, status: :unprocessable_entity
            end
          else
            render_not_found('Push subscription')
          end
        end

        # DELETE /api/v1/push/subscription
        def destroy
          if @subscription
            @subscription.destroy
            render json: {}
          else
            render_not_found('Push subscription')
          end
        end

        private

        def set_subscription
          @subscription = current_account.web_push_subscriptions.first
        end

        def extract_subscription_params
          subscription_data = params[:subscription]
          return nil unless subscription_data&.dig(:endpoint) && subscription_data[:keys]

          {
            endpoint: subscription_data[:endpoint],
            keys: {
              p256dh: subscription_data[:keys][:p256dh],
              auth: subscription_data[:keys][:auth]
            }
          }
        end

        def extract_alerts
          alerts_params = params.dig(:data, :alerts) || {}
          default_alerts = WebPushSubscription.new.default_alerts

          # Strong Parametersを適切に処理
          permitted_alerts = alerts_params.permit(*default_alerts.keys, 'admin.sign_up', 'admin.report')
          default_alerts.merge(permitted_alerts.to_h)
        end

        def serialized_subscription(subscription)
          {
            id: subscription.id.to_s,
            endpoint: subscription.endpoint,
            alerts: subscription.alerts,
            server_key: vapid_public_key,
            policy: subscription.data_hash['policy'] || 'all'
          }
        end

        def vapid_public_key
          ENV['VAPID_PUBLIC_KEY'] || Rails.application.credentials.dig(:vapid, :public_key)
        end
      end
    end
  end
end
