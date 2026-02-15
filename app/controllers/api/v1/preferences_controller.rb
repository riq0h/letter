# frozen_string_literal: true

module Api
  module V1
    class PreferencesController < Api::BaseController
      before_action :doorkeeper_authorize!
      before_action :require_user!

      # GET /api/v1/preferences
      def show
        render json: mastodon_preferences
      end

      private

      def mastodon_preferences
        prefs = current_user.preferences
        {
          default_privacy: prefs['posting:default:visibility'] || 'public',
          default_sensitive: prefs['posting:default:sensitive'] || false,
          default_language: prefs['posting:default:language'] || Rails.application.config.activitypub.default_locale,
          expand_spoilers: prefs['reading:expand:spoilers'] || false,
          use_blurhash: prefs['web:use_blurhash'] || true,
          use_pending_items: prefs['web:use_pending_items'] || false,
          trends: prefs['web:trends'] || true,
          crop_images: false,
          disable_swiping: false,
          always_send_emails: false,
          unfollow_modal: false,
          boost_modal: false,
          delete_modal: false,
          reduce_motion: false,
          system_font_ui: false,
          advanced_layout: prefs['web:advanced_layout'] || false,
          auto_play_gif: prefs['reading:autoplay:gifs'] || true,
          auto_play: 'default',
          display_media: prefs['reading:expand:media'] || 'default',
          show_application: true,
          theme: 'default',
          aggregate_reblogs: true
        }
      end
    end
  end
end
