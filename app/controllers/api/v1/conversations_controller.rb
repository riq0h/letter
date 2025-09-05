# frozen_string_literal: true

module Api
  module V1
    class ConversationsController < Api::BaseController
      include ConversationSerializer

      before_action :doorkeeper_authorize!
      before_action :set_conversation, only: %i[show destroy read]

      # GET /api/v1/conversations
      def index
        return render_authentication_required unless current_user

        conversations = current_user.conversations
                                    .includes(:participants, :last_status)
                                    .recent
                                    .limit(pagination_limit)

        conversations = apply_pagination(conversations)

        render json: conversations.map { |conversation| serialized_conversation(conversation) }
      end

      # GET /api/v1/conversations/:id
      def show
        render json: serialized_conversation(@conversation)
      end

      # DELETE /api/v1/conversations/:id
      def destroy
        return render_authentication_required unless current_user
        return render_not_found('Conversation') unless @conversation

        @conversation.destroy
        render json: {}, status: :ok
      end

      # POST /api/v1/conversations/:id/read
      def read
        return render_authentication_required unless current_user
        return render_not_found('Conversation') unless @conversation

        @conversation.mark_as_read!
        render json: serialized_conversation(@conversation)
      end

      private

      def set_conversation
        @conversation = current_user.conversations.find_by(id: params[:id])
      end

      def pagination_limit
        limit = params[:limit]&.to_i || 20
        [limit, 40].min # Mastodon API maximum is 40
      end

      def apply_pagination(conversations)
        conversations = apply_max_id_filter(conversations)
        conversations = apply_since_id_filter(conversations)
        apply_min_id_filter(conversations)
      end

      def apply_max_id_filter(conversations)
        return conversations if params[:max_id].blank?

        conversations.where(conversations: { id: ...(params[:max_id]) })
      end

      def apply_since_id_filter(conversations)
        return conversations if params[:since_id].blank?

        conversations.where('conversations.id > ?', params[:since_id])
      end

      def apply_min_id_filter(conversations)
        return conversations if params[:min_id].blank?

        conversations.where('conversations.id > ?', params[:min_id])
      end
    end
  end
end
