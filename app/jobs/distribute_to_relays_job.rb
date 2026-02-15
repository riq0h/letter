# frozen_string_literal: true

class DistributeToRelaysJob < ApplicationJob
  queue_as :default

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(object_id)
    object = ActivityPubObject.find(object_id)
    RelayDistributionService.new.distribute_to_relays(object)
  end
end
