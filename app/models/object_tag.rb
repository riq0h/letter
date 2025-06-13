# frozen_string_literal: true

class ObjectTag < ApplicationRecord
  belongs_to :object, class_name: 'ActivityPubObject'
  belongs_to :tag

  after_create :increment_tag_usage
  after_destroy :decrement_tag_usage

  private

  def increment_tag_usage
    tag.increment_usage!
  end

  def decrement_tag_usage
    tag.decrement_usage!
  end
end
