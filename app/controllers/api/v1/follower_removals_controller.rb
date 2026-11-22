# frozen_string_literal: true

module Api
  module V1
    # POST /api/v1/accounts/:id/remove_from_followers
    # 相手をフォロワーから外す。相手のサーバにもフォローを断ったことを伝える
    class FollowerRemovalsController < Api::BaseController
      include RelationshipSerializer

      before_action :doorkeeper_authorize!
      before_action :require_user!

      def create
        account = Actor.find_by(id: params[:id])
        return render_not_found('Account') unless account

        current_user.reverse_follows.find_by(actor: account)&.remove_follower!
        render json: serialized_relationship(account)
      end
    end
  end
end
