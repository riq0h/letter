# frozen_string_literal: true

# GET /emojis/:shortcode
# 投稿のtagに載せたEmojiのid。tagと同じ選び方(ローカル優先、無ければ他サーバの絵文字)で
# 同じ絵文字をActivityPubのEmojiとして返す(Mastodonの/emojis/:idに相当)
class EmojisController < ApplicationController
  def show
    emoji = EmojiPresenter.new(":#{params[:shortcode]}:").used_emojis.first
    return render json: { error: 'Emoji not found' }, status: :not_found unless emoji

    render json: {
      '@context' => Rails.application.config.activitypub.context_url,
      'updated' => emoji.updated_at&.iso8601
    }.merge(ActivityBuilders::TagBuilder.emoji_tag(emoji)).compact,
           content_type: 'application/activity+json; charset=utf-8'
  end
end
