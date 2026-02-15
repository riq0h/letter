# frozen_string_literal: true

module Api
  module V1
    class TagsController < Api::BaseController
      include SearchHashtagSerializer
      include HashtagHistoryBuilder

      # GET /api/v1/tags/:id
      def show
        tag_name = params[:id]
        tag = Tag.find_by(name: tag_name)

        if tag
          render json: serialized_hashtag_with_following(tag)
        else
          # タグが存在しない場合は基本的な情報で作成
          render json: {
            name: tag_name,
            url: "#{Rails.application.config.activitypub.base_url}/tags/#{tag_name}",
            history: [],
            following: false
          }
        end
      end

      # POST /api/v1/tags/:id/follow
      def follow
        doorkeeper_authorize! :write, :'write:follows'
        return render_authentication_required unless current_user

        tag_name = params[:id]
        tag = find_or_create_tag(tag_name)

        # フォロー関係を作成（重複チェック付き）
        current_user.followed_tags.find_or_create_by(tag: tag)

        render json: serialized_hashtag_with_following(tag, following: true)
      end

      # POST /api/v1/tags/:id/unfollow
      def unfollow
        doorkeeper_authorize! :write, :'write:follows'
        return render_authentication_required unless current_user

        tag_name = params[:id]
        tag = Tag.find_by(name: tag_name)

        if tag
          # フォロー関係を削除
          current_user.followed_tags.where(tag: tag).destroy_all
          render json: serialized_hashtag_with_following(tag, following: false)
        else
          render json: {
            name: tag_name,
            url: "#{Rails.application.config.activitypub.base_url}/tags/#{tag_name}",
            history: [],
            following: false
          }
        end
      end

      private

      def find_or_create_tag(tag_name)
        Tag.find_or_create_by(name: tag_name) do |tag|
          tag.usage_count = 0
        end
      end

      def serialized_hashtag_with_following(tag, following: nil)
        following_status = following || current_user&.followed_tags&.exists?(tag: tag)

        {
          name: tag.name,
          url: "#{Rails.application.config.activitypub.base_url}/tags/#{tag.name}",
          history: build_hashtag_history(tag),
          following: following_status
        }
      end
    end
  end
end
