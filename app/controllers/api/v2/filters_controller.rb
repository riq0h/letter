# frozen_string_literal: true

module Api
  module V2
    class FiltersController < Api::V1::FiltersController
      # V2フィルターAPIはV1と同一の実装
      # Mastodon API互換性のため両バージョンを提供
    end
  end
end
