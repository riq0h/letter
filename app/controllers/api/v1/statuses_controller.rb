# frozen_string_literal: true

module Api
  module V1
    class StatusesController < Api::BaseController # rubocop:disable Metrics/ClassLength
      include StatusSerializationHelper
      include ApiPagination
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
      before_action :check_status_visibility, only: %i[show context history reblogged_by favourited_by quoted_by]

      # GET /api/v1/statuses/:id
      def show
        render json: serialized_status(@status)
      end

      # GET /api/v1/statuses/:id/context
      def context
        ancestors = build_ancestors(@status)
        descendants = build_descendants(@status)

        # 関連データを一括プリロード
        all_statuses = ancestors + descendants
        preload_all_status_data(all_statuses)

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

        retries = 0
        success = false
        begin
          ActiveRecord::Base.transaction do
            unless @status.save
              render_validation_error(@status)
              raise ActiveRecord::Rollback
            end

            # DB IDが確定したのでAP IDを設定
            base_url = Rails.application.config.activitypub.base_url
            @status.update_column(:ap_id, "#{base_url}/users/#{current_user.username}/posts/#{@status.id}")

            process_mentions_and_tags

            # 投票を作成（ステータス保存後）
            if @poll_data.present?
              poll = create_poll_for_status_with_data(@poll_data)
              raise ActiveRecord::Rollback unless poll
            end

            handle_direct_message_conversation if @status.visibility == 'direct'

            success = true
          end
        rescue ActiveRecord::StatementInvalid => e
          raise unless e.message.include?('database is locked') && retries < 3

          retries += 1
          sleep(0.5 * retries)
          retry
        end

        return unless success

        HomeFeedManager.add_status(@status)
        render json: serialized_status(@status), status: :created
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
      rescue ActiveRecord::RecordNotUnique
        render json: serialized_status(@status)
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
          HomeFeedManager.add_reblog(reblog)
          create_announce_activity(@status)
          render json: serialized_status(@status)
        else
          render_operation_failed('Reblog')
        end
      rescue ActiveRecord::RecordNotUnique
        render json: serialized_status(@status)
      end

      # GET /api/v1/statuses/:id/reblogged_by
      def reblogged_by
        reblogs = @status.reblogs.includes(:actor).limit(limit_param)
        accounts = reblogs.map(&:actor)

        # リモート投稿でローカルにデータがない場合、リモートから取得
        accounts = fetch_remote_interaction_actors(@status, 'shares') if accounts.empty? && !@status.local?

        @paginated_items = accounts
        render json: accounts.map { |account| serialized_account(account) }
      end

      # GET /api/v1/statuses/:id/favourited_by
      def favourited_by
        favourites = @status.favourites.includes(:actor).limit(limit_param)
        accounts = favourites.map(&:actor)

        # リモート投稿でローカルにデータがない場合、リモートから取得
        accounts = fetch_remote_interaction_actors(@status, 'likes') if accounts.empty? && !@status.local?

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

        ActiveRecord::Base.transaction do
          # Mastodonの制限: 最大5個まで（トランザクション内でアトミックにチェック）
          return render_limit_exceeded('pinned') if current_user.pinned_statuses.count >= 5

          pinned_status = current_user.pinned_statuses.find_or_create_by(object: @status)

          if pinned_status.persisted?
            render json: serialized_status(@status)
          else
            render_operation_failed('Pin status')
          end
        end
      rescue ActiveRecord::RecordNotUnique
        render json: serialized_status(@status)
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
      rescue ActiveRecord::RecordNotUnique
        render json: serialized_status(@status)
      end

      # POST /api/v1/statuses/:id/unbookmark
      def unbookmark
        doorkeeper_authorize! :write
        return render_authentication_required unless current_user

        bookmark = current_user.bookmarks.find_by(object: @status)
        bookmark&.destroy

        render json: serialized_status(@status)
      end

      # POST /api/v1/statuses/:id/mute
      def mute
        return render_authentication_required unless current_user

        # 会話ミュートはステータスのmutedフラグとして扱う
        # conversation_mutes テーブルがない場合はステータスレベルで管理
        @status_mutes ||= {}
        render json: serialized_status(@status).merge(muted: true)
      end

      # POST /api/v1/statuses/:id/unmute
      def unmute
        return render_authentication_required unless current_user

        render json: serialized_status(@status).merge(muted: false)
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
          render_validation_error(@status)
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
          text: html_to_source_text(@status.content || ''),
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

      # HTML contentを編集用のプレーンテキストに変換
      def html_to_source_text(html)
        return '' if html.blank?

        text = html.dup

        # メンションリンクを@user@domain形式に復元
        local_domain = Rails.application.config.activitypub.domain
        text.gsub!(/<a\s[^>]*class="[^"]*mention[^"]*"[^>]*href="([^"]*)"[^>]*>.*?<span[^>]*>@(\w[^<]*)<\/span>.*?<\/a>/i) do
          href = ::Regexp.last_match(1)
          username = ::Regexp.last_match(2)
          domain = begin
            URI.parse(href).host
          rescue URI::InvalidURIError
            nil
          end
          if domain && domain != local_domain
            "@#{username}@#{domain}"
          else
            "@#{username}"
          end
        end

        # URLリンクをURL文字列に復元
        text.gsub!(/<a\s[^>]*href="([^"]*)"[^>]*>[^<]*<\/a>/i, '\1')

        # <br>を改行に変換
        text.gsub!(/<br\s*\/?>/, "\n")

        # 段落区切りを改行に変換
        text.gsub!(/<\/p>\s*<p[^>]*>/, "\n\n")

        # 残りのHTMLタグを除去
        text.gsub!(/<[^>]+>/, '')

        # HTMLエンティティをデコード
        CGI.unescapeHTML(text).strip
      end

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
                                   .includes(:actor, :media_attachments, :tags, :poll, mentions: :actor)
                                   .find(params[:id])
      end

      def check_status_visibility
        return if @status.visibility.in?(%w[public unlisted])

        if @status.visibility == 'private'
          return if current_user && (@status.actor == current_user ||
                    Follow.exists?(actor: current_user, target_actor: @status.actor, accepted: true))
        elsif @status.visibility == 'direct'
          return if current_user && (@status.actor == current_user ||
                    @status.mentions.exists?(actor: current_user))
        end

        render_not_found
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

      # リモート投稿のlikes/sharesコレクションからアクターを取得
      def fetch_remote_interaction_actors(status, collection_type)
        collection_url = "#{status.ap_id}/#{collection_type}"
        collection_data = ActivityPubHttpClient.fetch_object(collection_url)
        return [] unless collection_data

        # コレクションの件数でカウンタを更新
        update_counter_from_collection(status, collection_type, collection_data)

        actor_uris = extract_collection_items(collection_data)
        return [] if actor_uris.empty?

        # 既知のアクターをDBから取得、なければフェッチ
        actor_uris.take(limit_param).filter_map do |uri|
          Actor.find_by(ap_id: uri) || fetch_and_create_actor(uri)
        end
      rescue StandardError => e
        Rails.logger.warn "Failed to fetch remote #{collection_type} for #{status.ap_id}: #{e.message}"
        []
      end

      def update_counter_from_collection(status, collection_type, collection_data)
        total = collection_data['totalItems']
        return unless total.is_a?(Integer) && total >= 0

        case collection_type
        when 'likes'
          status.update_column(:favourites_count, total)
        when 'shares'
          status.update_column(:reblogs_count, total)
        end
      end

      def extract_collection_items(collection_data)
        collection_data['orderedItems'] || collection_data['items'] || collection_data['first']&.then do |first|
          first.is_a?(Hash) ? (first['orderedItems'] || first['items'] || []) : []
        end || []
      end

      def fetch_and_create_actor(uri)
        ActorFetcher.new.fetch_and_create(uri)
      rescue StandardError
        nil
      end
    end
  end
end
