# frozen_string_literal: true

module Api
  module V1
    module Admin
      class ReportsController < Api::BaseController
        include AdminAuthorization

        before_action :doorkeeper_authorize!
        before_action :require_admin!

        # GET /api/v1/admin/reports
        def index
          # letterでは簡素化されたレポート機能
          # 実際のレポートシステムは今回は未実装
          render json: []
        end

        # GET /api/v1/admin/reports/:id
        def show
          render_not_found('Report')
        end

        # POST /api/v1/admin/reports/:id/assign_to_self
        def assign_to_self
          render_not_implemented('Reports')
        end

        # POST /api/v1/admin/reports/:id/unassign
        def unassign
          render_not_implemented('Reports')
        end

        # POST /api/v1/admin/reports/:id/resolve
        def resolve
          render_not_implemented('Reports')
        end

        # POST /api/v1/admin/reports/:id/reopen
        def reopen
          render_not_implemented('Reports')
        end
      end
    end
  end
end
