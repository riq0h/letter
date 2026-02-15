# frozen_string_literal: true

module Api
  module V1
    class ConversationsController < Api::BaseController
      include ConversationSerializer
      include ApiPagination

      before_action :doorkeeper_authorize!
      before_action :require_user!
      before_action :set_conversation, only: %i[show destroy read]

      # GET /api/v1/conversations
      def index
        conversations = current_user.conversations
                                    .includes(:participants, :last_status)
                                    .recent
                                    .limit(limit_param)

        conversations = apply_collection_pagination(conversations, 'conversations')

        render json: conversations.map { |conversation| serialized_conversation(conversation) }
      end

      # GET /api/v1/conversations/:id
      def show
        render json: serialized_conversation(@conversation)
      end

      # DELETE /api/v1/conversations/:id
      def destroy
        return render_not_found('Conversation') unless @conversation

        @conversation.destroy
        render json: {}, status: :ok
      end

      # POST /api/v1/conversations/:id/read
      def read
        return render_not_found('Conversation') unless @conversation

        @conversation.mark_as_read!
        render json: serialized_conversation(@conversation)
      end

      private

      def set_conversation
        @conversation = current_user.conversations.find_by(id: params[:id])
      end
    end
  end
end
