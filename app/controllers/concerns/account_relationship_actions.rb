# frozen_string_literal: true

module AccountRelationshipActions
  extend ActiveSupport::Concern

  private

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
    handle_general_error(e, 'follow')
  end
end
