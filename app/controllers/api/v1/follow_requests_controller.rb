# frozen_string_literal: true

module Api
  module V1
    class FollowRequestsController < Api::BaseController
      before_action :doorkeeper_authorize!, only: %i[index authorize reject]
      before_action :require_user!, only: %i[index authorize reject]
      before_action :set_follow_request, only: %i[authorize reject]

      # GET /api/v1/follow_requests
      # 自分への未承認フォローリクエスト一覧を取得
      def index
        # 現在のユーザに対する未承認フォローリクエストを取得
        follow_requests = Follow.where(target_actor: current_user, accepted: false)
                                .includes(:actor)
                                .order(created_at: :desc)

        # Mastodon API形式でレスポンス
        accounts = follow_requests.map do |follow|
          account_json(follow.actor)
        end

        render json: accounts
      end

      # POST /api/v1/follow_requests/:id/authorize
      # フォローリクエストを承認
      def authorize
        if @follow_request.accepted?
          render_validation_failed('Follow request already authorized')
          return
        end

        ActiveRecord::Base.transaction do
          @follow_request.update!(accepted: true, accepted_at: Time.current)

          # フォロワー数を更新
          @follow_request.actor.increment!(:following_count)
          @follow_request.target_actor.increment!(:followers_count)
        end

        # Mastodon API準拠のRelationshipオブジェクトを返す
        render json: relationship_json(@follow_request.actor)
      end

      # POST /api/v1/follow_requests/:id/reject
      # フォローリクエストを拒否
      def reject
        if @follow_request.accepted?
          render_validation_failed('Follow request already authorized')
          return
        end

        @follow_request.destroy!

        # Mastodon API準拠のRelationshipオブジェクトを返す
        render json: relationship_json(@follow_request.actor)
      end

      private

      def set_follow_request
        @follow_request = Follow.where(target_actor: current_user, accepted: false)
                                .find_by(id: params[:id])

        return if @follow_request

        render_not_found('Follow request')
      end

      def account_json(actor)
        base_account_data(actor).merge(
          media_data(actor)
        ).merge(
          count_data(actor)
        ).merge(
          metadata_fields
        )
      end

      def base_account_data(actor)
        {
          id: actor.id.to_s,
          username: actor.username,
          acct: account_acct(actor),
          display_name: actor.display_name || actor.username,
          locked: false, # letter では基本的にfalse
          bot: false,
          discoverable: true,
          group: false,
          created_at: actor.created_at.iso8601,
          note: actor.note || '',
          url: actor.ap_id,
          last_status_at: actor.last_status_at&.iso8601
        }
      end

      def account_acct(actor)
        actor.local? ? actor.username : "#{actor.username}@#{actor.domain}"
      end

      def media_data(actor)
        {
          avatar: actor.avatar_url || '/avatars/missing.png',
          avatar_static: actor.avatar_url || '/avatars/missing.png',
          header: actor.header_url || '/headers/missing.png',
          header_static: actor.header_url || '/headers/missing.png'
        }
      end

      def count_data(actor)
        {
          followers_count: actor.followers_count || 0,
          following_count: actor.following_count || 0,
          statuses_count: actor.statuses_count || 0
        }
      end

      def metadata_fields
        {
          emojis: [],
          fields: []
        }
      end

      def relationship_json(actor)
        current_follows_actor = Follow.exists?(actor: current_user, target_actor: actor, accepted: true)
        actor_follows_current = Follow.exists?(actor: actor, target_actor: current_user, accepted: true)

        {
          id: actor.id.to_s,
          following: current_follows_actor,
          showing_reblogs: current_follows_actor,
          notifying: false,
          followed_by: actor_follows_current,
          blocking: false,
          blocked_by: false,
          muting: false,
          muting_notifications: false,
          requested: Follow.exists?(actor: current_user, target_actor: actor, accepted: false),
          domain_blocking: false,
          endorsed: false
        }
      end
    end
  end
end
