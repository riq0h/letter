# frozen_string_literal: true

module Api
  module V1
    class AccountsController < Api::BaseController
      include StatusSerializationHelper
      include ApiPagination
      include ValidationErrorRendering
      include FeaturedTagSerializer
      include AccountRelationshipActions
      include FileUploadHandler

      before_action :doorkeeper_authorize!, except: [:show]
      after_action :insert_pagination_headers, only: %i[statuses followers following]
      before_action :doorkeeper_authorize!, only: [:show], if: -> { request.authorization.present? }
      before_action :set_account, only: %i[show statuses followers following follow unfollow block unblock mute unmute note]
      before_action :set_account_for_featured_tags, only: [:featured_tags]

      # GET /api/v1/accounts/verify_credentials
      def verify_credentials
        doorkeeper_authorize!
        return render_authentication_required unless current_user

        render json: serialized_account(current_user, is_self: true)
      end

      # GET /api/v1/accounts/:id
      def show
        render json: serialized_account(@account)
      end

      # PATCH /api/v1/accounts/update_credentials
      def update_credentials
        return render_unauthorized unless current_user

        process_file_uploads
        update_account_attributes
      end

      # GET /api/v1/accounts/:id/statuses
      def statuses
        service_params = params.permit(:pinned, :exclude_replies, :only_media, :max_id, :since_id, :min_id)

        query = AccountStatusesQuery.new(@account, current_user)
        if service_params[:pinned] == 'true'
          # 固定投稿のみを取得
          pinned_statuses = query.pinned_only.limit(limit_param)
          statuses = pinned_statuses.map(&:object)
        else
          # 通常の投稿を取得

          # パラメータに応じてクエリを調整
          query = query.exclude_replies if service_params[:exclude_replies] == 'true'
          query = query.only_media if service_params[:only_media] == 'true'
          query = query.paginate(max_id: service_params[:max_id], since_id: service_params[:since_id], min_id: service_params[:min_id])

          statuses = query.with_includes.ordered.limit(limit_param).call
        end

        @paginated_items = statuses
        render json: statuses.map { |status| serialized_status(status) }
      end

      # GET /api/v1/accounts/:id/followers
      def followers
        if @account.local?
          followers = paginated_followers
          @paginated_items = followers
          render json: followers.map { |follower| serialized_account(follower) }
        else
          # 外部アカウントの場合は空配列を返す（クライアントが外部サーバから直接取得するため）
          render json: []
        end
      end

      # GET /api/v1/accounts/:id/following
      def following
        if @account.local?
          following = paginated_following
          @paginated_items = following
          render json: following.map { |followed| serialized_account(followed) }
        else
          # 外部アカウントの場合は空配列を返す（クライアントが外部サーバから直接取得するため）
          render json: []
        end
      end

      # POST /api/v1/accounts/:id/follow
      def follow
        return render_follow_error if cannot_follow_self?

        existing_follow = find_existing_follow
        return render_existing_follow_response(existing_follow) if existing_follow

        create_new_follow
      end

      # POST /api/v1/accounts/:id/unfollow
      def unfollow
        follow = current_user.follows.find_by(target_actor: @account)
        follow&.unfollow!

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/block
      def block
        return render_block_authentication_error unless current_user
        return render_block_self_error if @account == current_user

        process_block_action
        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/unblock
      def unblock
        return render_authentication_required unless current_user

        block = current_user.blocks.find_by(target_actor: @account)
        block&.destroy

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/mute
      def mute
        return render_authentication_required unless current_user
        return render_self_action_forbidden('mute') if @account == current_user

        notifications = params[:notifications] != false
        mute = current_user.mutes.find_or_initialize_by(target_actor: @account)
        mute.notifications = notifications
        mute.save!

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/unmute
      def unmute
        return render_authentication_required unless current_user

        mute = current_user.mutes.find_by(target_actor: @account)
        mute&.destroy

        render json: serialized_relationship(@account)
      end

      # GET /api/v1/accounts/search
      def search
        return unless doorkeeper_authorize! :read
        return render_authentication_required unless current_user

        query = params[:q].to_s.strip
        limit = [params.fetch(:limit, 40).to_i, 80].min
        resolve = params[:resolve] == 'true'

        return render json: [] if query.blank?

        accounts = search_accounts(query, limit, resolve: resolve)
        render json: accounts.map { |account| serialized_account(account) }
      end

      # GET /api/v1/accounts/:id/featured_tags
      def featured_tags
        featured_tags = @account.featured_tags.includes(:tag).recent
        render json: featured_tags.map { |featured_tag| serialized_featured_tag(featured_tag) }
      end

      # GET /api/v1/accounts/lookup
      def lookup
        return unless doorkeeper_authorize! :read
        return render_authentication_required unless current_user

        acct = params[:acct].to_s.strip
        return render_missing_parameter('acct') if acct.blank?

        account = lookup_account(acct)
        if account
          render json: serialized_account(account)
        else
          render_not_found
        end
      end

      # GET /api/v1/accounts/relationships
      def relationships
        return render_authentication_required unless current_user

        account_ids = Array(params[:id]).map(&:to_i)
        accounts = Actor.where(id: account_ids)

        # すべての要求されたIDに対してrelationshipを返す（存在しないものは空のrelationship）
        relationships = account_ids.map do |id|
          account = accounts.find { |a| a.id == id }
          if account
            serialized_relationship(account)
          else
            # 存在しないアカウントの場合、デフォルトrelationshipを返す
            { id: id.to_s, following: false, followed_by: false, showing_reblogs: true, notifying: false, requested: false, blocking: false,
              blocked_by: false, domain_blocking: false, muting: false, muting_notifications: false, endorsed: false }
          end
        end

        render json: relationships
      end

      # POST /api/v1/accounts/:id/note
      def note
        return render_authentication_required unless current_user

        comment = params[:comment] || ''

        if comment.blank?
          current_user.account_notes.find_by(target_actor: @account)&.destroy
        else
          note = current_user.account_notes.find_or_initialize_by(target_actor: @account)
          note.comment = comment

          return render_validation_failed_with_details('Failed to save note', note.errors.full_messages) unless note.save
        end

        render json: serialized_relationship(@account)
      end

      private

      def cannot_follow_self?
        @account == current_user
      end

      def render_follow_error
        render_self_action_forbidden('follow')
      end

      def find_existing_follow
        current_user.follows.find_by(target_actor: @account)
      end

      def render_existing_follow_response(existing_follow)
        log_existing_follow_status(existing_follow)
        render json: serialized_relationship(@account)
      end

      def log_existing_follow_status(existing_follow)
        if existing_follow.accepted?
          Rails.logger.info "Already following #{@account.ap_id}"
        else
          Rails.logger.info "Follow request already sent to #{@account.ap_id}"
        end
      end

      def set_account
        @account = Actor.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def account_params
        params.permit(:display_name, :note, :locked, :bot, :discoverable, :avatar, :header, fields_attributes: %i[name value])
      end

      def serialized_relationship(account)
        return {} unless current_user

        { id: account.id.to_s, **follow_relationship_data(account), **blocking_relationship_data(account), **muting_relationship_data(account),
          **additional_relationship_data(account) }
      end

      def follow_relationship_data(account)
        following_relationship = Follow.find_by(actor: current_user, target_actor: account)
        followed_by_relationship = Follow.find_by(actor: account, target_actor: current_user)

        { following: following_relationship&.accepted? || false, followed_by: followed_by_relationship&.accepted? || false, showing_reblogs: true,
          notifying: false, requested: following_relationship&.pending? || false }
      end

      def blocking_relationship_data(account)
        { blocking: current_user.blocking?(account), blocked_by: current_user.blocked_by?(account),
          domain_blocking: account.domain.present? ? current_user.domain_blocking?(account.domain) : false }
      end

      def muting_relationship_data(account)
        mute = current_user.mutes.find_by(target_actor: account)
        { muting: current_user.muting?(account), muting_notifications: mute&.notifications || false }
      end

      def additional_relationship_data(account)
        note = current_user.account_notes.find_by(target_actor: account)
        { endorsed: false, note: note&.comment || '' }
      end

      def render_block_authentication_error
        render_authentication_required
      end

      def render_block_self_error
        render_self_action_forbidden('block')
      end

      def process_block_action
        # 既存のフォロー関係を削除（双方向）
        current_user.follows.find_by(target_actor: @account)&.destroy
        @account.follows.find_by(target_actor: current_user)&.destroy

        # ブロックを作成
        current_user.blocks.find_or_create_by(target_actor: @account)
      end

      def search_accounts(query, limit, resolve: false)
        # ローカル検索を実行
        local_accounts = Actor.where(
          'username LIKE ? OR display_name LIKE ?',
          "%#{query}%", "%#{query}%"
        ).limit(limit)

        # resolveがtrueで、ローカル結果が少ない場合はWebFinger解決を試行
        if resolve && local_accounts.count < limit && query.include?('@')
          remote_account = resolve_remote_account(query)
          local_accounts = [remote_account] + local_accounts.to_a if remote_account && local_accounts.exclude?(remote_account)
        end

        local_accounts
      end

      def lookup_account(acct)
        # URL形式の場合
        if acct.match?(/^https?:\/\//)
          uri = URI.parse(acct)
          return nil unless uri.host == Rails.application.config.activitypub.domain

          # /users/username 形式のパスを解析
          if uri.path =~ /^\/users\/([^\/]+)$/
            username = ::Regexp.last_match(1)
            Actor.find_by(username: username, local: true)
          end
        elsif acct.include?('@')
          username, domain = acct.split('@', 2)
          # まずローカルDBから検索
          actor = Actor.find_by(username: username, domain: domain)

          # 見つからない場合はWebFinger解決を試行
          actor ||= resolve_remote_account(acct)

          actor
        else
          Actor.find_by(username: acct, local: true)
        end
      end

      def resolve_remote_account(query)
        resolver = Search::RemoteResolverService.new
        resolver.resolve_remote_account(query)
      end

      def set_account_for_featured_tags
        @account = Actor.find(params[:id])
      end

      def paginated_followers
        base_query = @account.followers.order(id: :desc)

        if params[:max_id].present?
          # max_idより小さいIDのフォロワーを取得
          base_query = base_query.where(actors: { id: ...(params[:max_id]) })
        end

        if params[:since_id].present?
          # since_idより大きいIDのフォロワーを取得
          base_query = base_query.where('actors.id > ?', params[:since_id])
        end

        base_query.limit(limit_param)
      end

      def paginated_following
        base_query = @account.followed_actors.order(id: :desc)

        if params[:max_id].present?
          # max_idより小さいIDのフォロー中アカウントを取得
          base_query = base_query.where(actors: { id: ...(params[:max_id]) })
        end

        if params[:since_id].present?
          # since_idより大きいIDのフォロー中アカウントを取得
          base_query = base_query.where('actors.id > ?', params[:since_id])
        end

        base_query.limit(limit_param)
      end
    end
  end
end
