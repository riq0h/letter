# frozen_string_literal: true

module ListSerializer
  extend ActiveSupport::Concern

  private

  def serialized_list(list)
    {
      id: list.id.to_s,
      title: list.title,
      replies_policy: list.replies_policy,
      exclusive: list.exclusive
    }
  end
end
