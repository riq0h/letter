# frozen_string_literal: true

module ActivityPubVisibilityHelper
  extend ActiveSupport::Concern

  private

  def determine_visibility(object_data)
    to = Array(object_data['to'])
    cc = Array(object_data['cc'])

    return 'public' if to.include?('https://www.w3.org/ns/activitystreams#Public')
    return 'unlisted' if cc.include?('https://www.w3.org/ns/activitystreams#Public')
    return 'direct' if to.any? && cc.empty?

    'private'
  end
end
