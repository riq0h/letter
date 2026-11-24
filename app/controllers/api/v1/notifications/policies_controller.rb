# frozen_string_literal: true

module Api
  module V1
    module Notifications
      # 通知の受け取り制限の設定(Mastodon 4.3以降のAPI)。letterには受け取り制限の機能が無く、
      # すべての通知を受け取るので、その状態をMastodonと同じ形で返す
      class PoliciesController < Api::BaseController
        before_action :doorkeeper_authorize!
        before_action :require_user!

        # GET /api/v1/notifications/policy
        def show
          render json: {
            filter_not_following: false,
            filter_not_followers: false,
            filter_new_accounts: false,
            filter_private_mentions: false,
            summary: { pending_requests_count: 0, pending_notifications_count: 0 }
          }
        end
      end
    end
  end
end
