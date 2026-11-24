# frozen_string_literal: true

module Api
  module V2
    module Notifications
      # 通知の受け取り制限の設定(Mastodon 4.3以降のAPI)。letterには受け取り制限の機能が無く、
      # すべての通知を受け取るので、どの相手も"accept"として返す
      class PoliciesController < Api::BaseController
        before_action :doorkeeper_authorize!
        before_action :require_user!

        # GET /api/v2/notifications/policy
        def show
          render json: {
            for_not_following: 'accept',
            for_not_followers: 'accept',
            for_new_accounts: 'accept',
            for_private_mentions: 'accept',
            for_limited_accounts: 'accept',
            summary: { pending_requests_count: 0, pending_notifications_count: 0 }
          }
        end
      end
    end
  end
end
