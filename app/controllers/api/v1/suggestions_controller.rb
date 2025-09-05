# frozen_string_literal: true

module Api
  module V1
    class SuggestionsController < Api::BaseController
      include AccountSerializer

      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v1/suggestions
      def index
        limit = [params[:limit].to_i, 40].min
        limit = 20 if limit <= 0

        suggestions = generate_suggestions(limit)
        render json: suggestions.map { |actor| serialized_suggestion(actor) }
      end

      # DELETE /api/v1/suggestions/:id
      def destroy
        # letterでは推奨機能のカスタマイズは簡素化
        # 削除リクエストは受け入れるが、実際の処理は行わない
        render json: {}
      end

      private

      def generate_suggestions(limit)
        # letterでは2ユーザ制限なので、ローカルアカウントは推奨対象外
        # 既にフォローしていないリモートユーザから推奨
        already_following_ids = current_user.following.pluck(:id)

        Actor.remote
             .where.not(id: already_following_ids)
             .where('followers_count > ?', 0) # ある程度人気のあるアカウント
             .order('followers_count DESC, created_at DESC')
             .limit(limit)
      end

      def serialized_suggestion(actor)
        {
          source: 'featured', # Mastodon互換の推奨理由
          account: serialized_account(actor)
        }
      end

      # AccountSerializer から継承されたメソッドを使用
    end
  end
end
