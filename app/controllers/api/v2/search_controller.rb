# frozen_string_literal: true

module Api
  module V2
    class SearchController < Api::BaseController
      include SearchSerializationHelper

      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v2/search
      def index
        @results = perform_search
        render_search_results
      end

      private

      def perform_search
        result = SearchInteractor.search(params, current_user)

        if result.success?
          result.results
        else
          Rails.logger.error "Search failed: #{result.error}"
          { accounts: [], statuses: [], hashtags: [] }
        end
      end

      def render_search_results
        preload_search_emojis(@results[:statuses]) if @results[:statuses].present?

        render json: {
          accounts: @results[:accounts].map { |account| serialized_account(account) },
          statuses: @results[:statuses].map { |status| serialized_status(status) },
          hashtags: @results[:hashtags].map { |hashtag| serialized_hashtag(hashtag) }
        }
      end

      def preload_search_emojis(statuses)
        all_shortcodes = Set.new
        domain_shortcodes = Hash.new { |h, k| h[k] = Set.new }

        statuses.each do |status|
          next if status.content.blank?

          shortcodes = EmojiPresenter.extract_shortcodes_from(status.content)
          all_shortcodes.merge(shortcodes)
          domain = status.actor&.domain
          domain_shortcodes[domain].merge(shortcodes) if domain.present?
        end
        return if all_shortcodes.empty?

        local_emojis = CustomEmoji.enabled.visible.where(shortcode: all_shortcodes.to_a, domain: nil).index_by(&:shortcode)
        remote_emojis = {}
        domain_shortcodes.each do |domain, codes|
          CustomEmoji.enabled.remote.where(shortcode: codes.to_a, domain: domain).find_each do |emoji|
            remote_emojis["#{emoji.shortcode}:#{domain}"] = emoji
          end
        end

        @emoji_cache = { local: local_emojis, remote: remote_emojis }
      end
    end
  end
end
