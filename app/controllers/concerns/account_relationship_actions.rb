# frozen_string_literal: true

module AccountRelationshipActions
  extend ActiveSupport::Concern

  private

  def process_block_action
    return render_block_authentication_error unless current_user
    return render_block_self_error if @account == current_user

    # 既存のフォロー関係を削除
    @account.follows.find_by(target_actor: current_user)&.destroy
    current_user.follows.find_by(target_actor: @account)&.destroy

    # ブロックを作成
    current_user.blocks.find_or_create_by(target_actor: @account)

    render json: serialized_relationship(@account)
  end

  def render_block_authentication_error
    render_authentication_required
  end

  def render_block_self_error
    render_self_action_forbidden('block')
  end

  def search_accounts(query, limit, resolve: false)
    # ローカル検索を実行
    local_accounts = Actor.where(
      'username LIKE ? OR display_name LIKE ?',
      "%#{query}%", "%#{query}%"
    ).where(local: true).limit(limit)

    # リモート検索が要求された場合
    if resolve && local_accounts.empty?
      begin
        # WebFingerでリモートアカウントを検索
        resolved_account = Search::RemoteResolverService.new(query: query).resolve_account
        local_accounts = [resolved_account].compact if resolved_account
      rescue StandardError => e
        Rails.logger.warn "Remote account resolution failed: #{e.message}"
      end
    end

    local_accounts
  end

  def create_new_follow
    Rails.logger.info "🔗 Creating follow from #{current_user.username} to #{@account.username}@#{@account.domain}"

    result = FollowInteractor.follow(current_user, @account)

    if result.success?
      Rails.logger.info "✅ Follow request created for #{@account.ap_id}"
      render json: serialized_relationship(@account)
    else
      Rails.logger.error "❌ Failed to create follow relationship: #{result.error}"
      render_validation_failed_with_details('Follow failed', [result.error])
    end
  rescue StandardError => e
    Rails.logger.error "💥 Exception in create_new_follow: #{e.class}: #{e.message}"
    render json: { error: 'Internal Server Error' }, status: :internal_server_error
  end
end
