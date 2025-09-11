# frozen_string_literal: true

module Api
  module V1
    class StatusesController < Api::BaseController
      include AccountSerializer
      include StatusSerializer
      include MediaSerializer
      include MentionTagSerializer
      include StatusActivityHandlers
      include StatusSerializationHelper
      include TextLinkingHelper
      include ApiPagination
      include ValidationErrorRendering
      include StatusActions
      include ScheduledStatusHandling
      include StatusContextBuilder
      include StatusEditHandler
      include QuotePostHandler
      include StatusCreationHandler
      include StatusParamsHandler
      include MentionProcessor

      before_action :doorkeeper_authorize!, except: [:show]
      after_action :insert_pagination_headers, only: %i[reblogged_by favourited_by]
      before_action :doorkeeper_authorize!, only: [:show], if: -> { request.authorization.present? }
      before_action :set_status, except: [:create]

      # GET /api/v1/statuses/:id
      def show
        render json: serialized_status(@status)
      end

      # GET /api/v1/statuses/:id/context
      def context
        ancestors = build_ancestors(@status)
        descendants = build_descendants(@status)

        # リプライ先情報をプリロード
        all_statuses = ancestors + descendants
        preload_reply_to_data(all_statuses)

        render json: {
          ancestors: ancestors.map { |status| serialized_status(status) },
          descendants: descendants.map { |status| serialized_status(status) }
        }
      end

      # POST /api/v1/statuses
      def create
        return render_authentication_required unless current_user

        # 予約投稿の処理
        return create_scheduled_status if params[:scheduled_at].present?

        @status = build_status_object
        attach_media_to_status if @media_ids&.any?

        # 投票パラメータがある場合は先に作成
        if poll_params.present?
          # 一時的に投票データを保存
          @poll_data = poll_params
        end

        if @status.save
          # DB IDが確定したのでAP IDを設定
          base_url = Rails.application.config.activitypub.base_url
          @status.update_column(:ap_id, "#{base_url}/users/#{current_user.username}/posts/#{@status.id}")

          process_mentions_and_tags

          # 投票を作成（ステータス保存後）
          if @poll_data.present?
            poll = create_poll_for_status_with_data(@poll_data)
            unless poll
              @status.destroy
              return render_operation_failed('Create poll')
            end
          end

          handle_direct_message_conversation if @status.visibility == 'direct'

          render json: serialized_status(@status), status: :created
        else
          render_validation_error(@status)
        end
      end

      # POST /api/v1/statuses/:id/favourite
      def favourite
        return render_authentication_required unless current_user

        favourite = current_user.favourites.find_or_create_by(object: @status)

        if favourite.persisted?
          create_like_activity(@status)
          render json: serialized_status(@status)
        else
          render_operation_failed('Favourite')
        end
      end

      # POST /api/v1/statuses/:id/unfavourite
      def unfavourite
        return render_authentication_required unless current_user

        favourite = current_user.favourites.find_by(object: @status)

        if favourite
          create_undo_like_activity(@status, favourite)
          favourite.destroy
        end

        render json: serialized_status(@status)
      end

      # POST /api/v1/statuses/:id/reblog
      def reblog
        return render_authentication_required unless current_user

        reblog = current_user.reblogs.find_or_create_by(object: @status)

        if reblog.persisted?
          create_announce_activity(@status)
          render json: serialized_status(@status)
        else
          render_operation_failed('Reblog')
        end
      end

      # GET /api/v1/statuses/:id/reblogged_by
      def reblogged_by
        reblogs = @status.reblogs.includes(:actor).limit(limit_param)
        accounts = reblogs.map(&:actor)
        @paginated_items = accounts
        render json: accounts.map { |account| serialized_account(account) }
      end

      # GET /api/v1/statuses/:id/favourited_by
      def favourited_by
        favourites = @status.favourites.includes(:actor).limit(limit_param)
        accounts = favourites.map(&:actor)
        @paginated_items = accounts
        render json: accounts.map { |account| serialized_account(account) }
      end

      # POST /api/v1/statuses/:id/quote
      def quote
        return render_authentication_required unless current_user

        quote_params = build_quote_params
        quoted_status = @status

        # 新しいポストオブジェクトを作成
        @status = build_quote_status_object(quoted_status, quote_params)

        if @status.save
          # DB IDが確定したのでAP IDを設定
          base_url = Rails.application.config.activitypub.base_url
          @status.update_column(:ap_id, "#{base_url}/users/#{current_user.username}/posts/#{@status.id}")

          create_quote_post_record(quoted_status, @status)
          process_mentions_and_tags if @status.content.present?
          @status.create_quote_activity(quoted_status) if @status.local?
          render json: serialized_status(@status), status: :created
        else
          render_validation_error(@status)
        end
      end

      # GET /api/v1/statuses/:id/quoted_by
      def quoted_by
        limit = [params.fetch(:limit, 40).to_i, 80].min
        quotes = @status.quotes_of_this.includes(:actor, :object).limit(limit)

        # 引用したアクターを返す
        accounts = quotes.map(&:actor).uniq
        render json: accounts.map { |account| serialized_account(account) }
      end

      # POST /api/v1/statuses/:id/unreblog
      def unreblog
        return render_authentication_required unless current_user

        reblog = current_user.reblogs.find_by(object: @status)

        if reblog
          create_undo_announce_activity(@status, reblog)
          reblog.destroy
        end

        render json: serialized_status(@status)
      end

      # POST /api/v1/statuses/:id/pin
      def pin
        return render_authentication_required unless current_user
        return render_insufficient_permission('pin your own statuses') unless @status.actor == current_user

        # Mastodonの制限: 最大5個まで
        return render_limit_exceeded('pinned') if current_user.pinned_statuses.count >= 5

        pinned_status = current_user.pinned_statuses.find_or_create_by(object: @status)

        if pinned_status.persisted?
          render json: serialized_status(@status)
        else
          render_operation_failed('Pin status')
        end
      end

      # POST /api/v1/statuses/:id/unpin
      def unpin
        return render_authentication_required unless current_user

        pinned_status = current_user.pinned_statuses.find_by(object: @status)
        pinned_status&.destroy

        render json: serialized_status(@status)
      end

      # POST /api/v1/statuses/:id/bookmark
      def bookmark
        doorkeeper_authorize! :write
        return render_authentication_required unless current_user

        bookmark = current_user.bookmarks.find_or_create_by(object: @status)

        if bookmark.persisted?
          render json: serialized_status(@status)
        else
          render_operation_failed('Bookmark')
        end
      end

      # POST /api/v1/statuses/:id/unbookmark
      def unbookmark
        doorkeeper_authorize! :write
        return render_authentication_required unless current_user

        bookmark = current_user.bookmarks.find_by(object: @status)
        bookmark&.destroy

        render json: serialized_status(@status)
      end

      # PUT /api/v1/statuses/:id
      def update
        return render_authentication_required unless current_user
        return render_not_authorized unless @status.actor == current_user

        edit_params = build_edit_params

        if @status.perform_edit!(edit_params)
          # メンションやタグの再処理
          process_mentions_and_tags_for_edit(edit_params) if edit_params[:content]

          render json: serialized_status(@status)
        else
          render json: { error: 'Validation failed', details: @status.errors.full_messages },
                 status: :unprocessable_entity
        end
      end

      # GET /api/v1/statuses/:id/history
      def history
        edits = @status.status_edits.order(:created_at) # 古いものから新しい順

        # 編集履歴が空の場合は現在の状態のみ
        if edits.empty?
          render json: [build_current_version]
          return
        end

        # Mastodon API仕様: 編集履歴は時系列順
        # 各StatusEditレコードは編集前の状態を保存している
        # つまり: Edit0=オリジナル, Edit1=1回目編集前, Edit2=2回目編集前...
        # 表示順序: オリジナル → 1回目編集後 → 2回目編集後 → ... → 現在

        versions = []

        # 編集レコードから各時点の状態を構築
        edits.each_with_index do |edit, index|
          edit_version = build_edit_version(edit)

          # 最初の編集レコード = オリジナル投稿
          edit_version[:created_at] = if index.zero?
                                        @status.published_at.iso8601
                                      else
                                        # 前の編集レコードの作成時刻 = この状態が存在していた時刻
                                        edits[index - 1].created_at.iso8601
                                      end

          versions << edit_version
        end

        # 最後に現在の状態を追加
        current_version = build_current_version
        current_version[:created_at] = edits.last.created_at.iso8601
        versions << current_version

        render json: versions
      end

      # GET /api/v1/statuses/:id/source
      def source
        doorkeeper_authorize! :read
        return render_authentication_required unless current_user
        return render_not_authorized unless @status.actor == current_user

        render json: {
          id: @status.id.to_s,
          text: @status.content || '',
          spoiler_text: @status.summary || ''
        }
      end

      # DELETE /api/v1/statuses/:id
      def destroy
        return render_authentication_required unless current_user
        return render_not_authorized unless @status.actor == current_user

        @status.destroy
        render json: serialized_status(@status)
      end

      private

      def build_status_object
        current_user.objects.build(status_creation_params)
      end

      def status_creation_params
        status_params.merge(
          object_type: 'Note',
          published_at: Time.current,
          local: true
        )
      end

      def attach_media_to_status
        media_attachments = current_user.media_attachments.where(
          id: @media_ids,
          object_id: nil,
          processed: true
        )
        @status.media_attachments = media_attachments
      end

      def set_status
        @status = ActivityPubObject.where(object_type: %w[Note Question])
                                   .includes(:poll)
                                   .find(params[:id])
      end

      def handle_direct_message_conversation
        return unless @status.visibility == 'direct'

        # DMの場合はメンションされたアクターを参加者として追加
        mentioned_actors = @status.mentioned_actors.to_a
        participants = [current_user] + mentioned_actors

        # 会話を作成または取得
        conversation = Conversation.find_or_create_for_actors(participants)

        # ステータスを会話に関連付け
        @status.update!(conversation: conversation)

        # 会話の最新ステータスを更新
        conversation.update_last_status!(@status)
      end
    end
  end
end
