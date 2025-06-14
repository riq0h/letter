# frozen_string_literal: true

module Api
  module V1
    class AccountsController < Api::BaseController
      include AccountSerializer
      before_action :doorkeeper_authorize!, except: [:show]
      before_action :doorkeeper_authorize!, only: [:show], if: -> { request.authorization.present? }
      before_action :set_account, except: %i[verify_credentials]

      # GET /api/v1/accounts/verify_credentials
      def verify_credentials
        doorkeeper_authorize!
        return render json: { error: 'This action requires authentication' }, status: :unauthorized unless current_user

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
        statuses = @account.objects
                           .where(object_type: 'Note')
                           .where(local: true)
                           .order(published_at: :desc)
                           .limit(20)

        render json: statuses.map { |status| serialized_status(status) }
      end

      # GET /api/v1/accounts/:id/followers
      def followers
        followers = @account.followers.limit(40)
        render json: followers.map { |follower| serialized_account(follower) }
      end

      # GET /api/v1/accounts/:id/following
      def following
        following = @account.followed_actors.limit(40)
        render json: following.map { |followed| serialized_account(followed) }
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
        return render json: { error: 'This action requires authentication' }, status: :unauthorized unless current_user
        return render json: { error: 'Cannot block yourself' }, status: :unprocessable_entity if @account == current_user

        # Remove any existing follow relationship first
        existing_follow = current_user.follows.find_by(target_actor: @account)
        existing_follow&.destroy

        # Create block
        current_user.blocks.find_or_create_by(target_actor: @account)

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/unblock
      def unblock
        return render json: { error: 'This action requires authentication' }, status: :unauthorized unless current_user

        block = current_user.blocks.find_by(target_actor: @account)
        block&.destroy

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/mute
      def mute
        return render json: { error: 'This action requires authentication' }, status: :unauthorized unless current_user
        return render json: { error: 'Cannot mute yourself' }, status: :unprocessable_entity if @account == current_user

        notifications = params[:notifications] != false
        mute = current_user.mutes.find_or_initialize_by(target_actor: @account)
        mute.notifications = notifications
        mute.save!

        render json: serialized_relationship(@account)
      end

      # POST /api/v1/accounts/:id/unmute
      def unmute
        return render json: { error: 'This action requires authentication' }, status: :unauthorized unless current_user

        mute = current_user.mutes.find_by(target_actor: @account)
        mute&.destroy

        render json: serialized_relationship(@account)
      end

      private

      def cannot_follow_self?
        @account == current_user
      end

      def render_follow_error
        render json: { error: 'Cannot follow yourself' }, status: :unprocessable_content
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

      def create_new_follow
        follow = current_user.follows.build(target_actor: @account)

        if follow.save
          Rails.logger.info "Follow request created for #{@account.ap_id}"
          render json: serialized_relationship(@account)
        else
          render_follow_creation_error(follow)
        end
      end

      def render_follow_creation_error(follow)
        Rails.logger.error "Failed to create follow: #{follow.errors.full_messages}"
        render json: { error: 'Follow failed', details: follow.errors.full_messages }, status: :unprocessable_entity
      end

      def set_account
        @account = Actor.find(params[:id])
      end

      def account_params
        params.permit(:display_name, :summary, :locked, :bot, :discoverable, :avatar, :header)
      end

      def handle_avatar_upload
        return unless valid_upload?(params[:avatar])

        process_image_upload(params[:avatar], 'avatars', :icon_url)
      end

      def handle_header_upload
        return unless valid_upload?(params[:header])

        process_image_upload(params[:header], 'headers', :header_url)
      end

      def file_extension(filename)
        File.extname(filename).downcase.delete('.')
      end

      def render_unauthorized
        render json: { error: 'This action requires authentication' }, status: :unauthorized
      end

      def process_file_uploads
        handle_avatar_upload if params[:avatar].present?
        handle_header_upload if params[:header].present?
      end

      def update_account_attributes
        if current_user.update(account_params.except(:avatar, :header))
          render json: serialized_account(current_user, is_self: true)
        else
          render_validation_error
        end
      end

      def render_validation_error
        render json: {
          error: 'Validation failed',
          details: current_user.errors.full_messages
        }, status: :unprocessable_entity
      end

      def valid_upload?(file)
        file&.respond_to?(:tempfile)
      end

      def process_image_upload(uploaded_file, folder, url_attribute)
        filename = generate_filename(uploaded_file.original_filename, folder)
        file_path = build_file_path(folder, filename)

        save_uploaded_file(uploaded_file, file_path)
        update_user_url(url_attribute, folder, filename)
        log_upload_success(folder, filename)
      end

      def generate_filename(original_filename, folder_type)
        timestamp = Time.current.to_i
        extension = file_extension(original_filename)
        "#{current_user.username}_#{folder_type.singularize}_#{timestamp}.#{extension}"
      end

      def build_file_path(folder, filename)
        Rails.public_path.join('system', 'accounts', folder, filename)
      end

      def save_uploaded_file(uploaded_file, file_path)
        FileUtils.mkdir_p(File.dirname(file_path))
        FileUtils.cp(uploaded_file.tempfile.path, file_path)
      end

      def update_user_url(url_attribute, folder, filename)
        base_url = Rails.application.config.activitypub.base_url
        file_url = "#{base_url}/system/accounts/#{folder}/#{filename}"
        current_user.update_column(url_attribute, file_url)
      end

      def log_upload_success(folder, filename)
        Rails.logger.info "#{folder.capitalize.singularize} uploaded for #{current_user.username}: #{filename}"
      end

      def serialized_status(status)
        {
          id: status.id.to_s,
          created_at: status.published_at.iso8601,
          in_reply_to_id: nil,
          in_reply_to_account_id: nil,
          sensitive: status.sensitive || false,
          spoiler_text: status.summary || '',
          visibility: status.visibility || 'public',
          language: 'ja',
          uri: status.ap_id,
          url: status.public_url,
          replies_count: 0,
          reblogs_count: 0,
          favourites_count: 0,
          content: status.content || '',
          reblog: nil,
          account: serialized_account(status.actor),
          media_attachments: [],
          mentions: [],
          tags: [],
          emojis: [],
          card: nil,
          poll: nil
        }
      end

      def serialized_relationship(account)
        return {} unless current_user

        {
          id: account.id.to_s,
          **follow_relationship_data(account),
          **blocking_relationship_data(account),
          **muting_relationship_data(account),
          **additional_relationship_data(account)
        }
      end

      def follow_relationship_data(account)
        {
          following: current_user.followed_actors.include?(account),
          followed_by: account.followers.include?(current_user),
          showing_reblogs: true,
          notifying: false,
          requested: false
        }
      end

      def blocking_relationship_data(account)
        {
          blocking: current_user.blocking?(account),
          blocked_by: current_user.blocked_by?(account),
          domain_blocking: account.domain.present? ? current_user.domain_blocking?(account.domain) : false
        }
      end

      def muting_relationship_data(account)
        mute = current_user.mutes.find_by(target_actor: account)
        {
          muting: current_user.muting?(account),
          muting_notifications: mute&.notifications || false
        }
      end

      def additional_relationship_data(_account)
        {
          endorsed: false
        }
      end

      def default_avatar_url
        '/icon.png'
      end

      def default_header_url
        '/icon.png'
      end
    end
  end
end
