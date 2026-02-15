# frozen_string_literal: true

module Api
  module V1
    module Admin
      class AccountsController < Api::BaseController
        include AdminAuthorization
        include AccountSerializer

        before_action :doorkeeper_authorize!
        before_action :require_admin!
        before_action :set_account, except: [:index]

        # GET /api/v1/admin/accounts
        def index
          accounts = Actor.includes(:web_push_subscriptions)
                          .order(created_at: :desc)
                          .limit(params[:limit]&.to_i || 40)

          if params[:local] == 'true'
            accounts = accounts.local
          elsif params[:remote] == 'true'
            accounts = accounts.remote
          end

          render json: accounts.map { |account| admin_account_json(account) }
        end

        # GET /api/v1/admin/accounts/:id
        def show
          render json: admin_account_json(@account)
        end

        # POST /api/v1/admin/accounts/:id/enable
        def enable
          @account.update!(suspended: false)
          render json: admin_account_json(@account)
        end

        # POST /api/v1/admin/accounts/:id/suspend
        def suspend
          @account.update!(suspended: true)
          render json: admin_account_json(@account)
        end

        # DELETE /api/v1/admin/accounts/:id
        def destroy
          return render_error('Cannot delete local admin account', 403) if @account.local? && @account.admin?

          @account.destroy!
          render json: {}
        end

        private

        def set_account
          @account = Actor.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found('Account')
        end

        def admin_account_json(account)
          {
            id: account.id.to_s,
            username: account.username,
            domain: account.domain,
            created_at: account.created_at.iso8601,
            email: account.local? ? "#{account.username}@localhost" : nil,
            ip: account.local? ? '127.0.0.1' : nil,
            role: account.admin? ? 'admin' : 'user',
            confirmed: true,
            suspended: account.suspended || false,
            silenced: false,
            disabled: false,
            approved: true,
            locale: 'ja',
            account: serialized_account(account)
          }
        end
      end
    end
  end
end
