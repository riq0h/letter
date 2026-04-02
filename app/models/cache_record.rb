# frozen_string_literal: true

class CacheRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :cache, reading: :cache }
end
