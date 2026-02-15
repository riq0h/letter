# frozen_string_literal: true

module StatusCreationHandler
  extend ActiveSupport::Concern

  private

  def create_poll_for_status_with_data(poll_data)
    PollCreationService.create_for_status(@status, poll_data)
  end
end
