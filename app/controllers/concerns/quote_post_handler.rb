# frozen_string_literal: true

module QuotePostHandler
  extend ActiveSupport::Concern

  private

  def build_quote_params
    quote_params = {
      content: params[:status] || '',
      summary: params[:spoiler_text],
      sensitive: params[:sensitive] == 'true',
      language: params[:language] || current_user.locale || 'ja',
      local: true
    }

    # メディア添付があれば追加
    quote_params[:media_attachment_ids] = @media_ids if @media_ids&.any?

    quote_params
  end

  def build_quote_status_object(quoted_status, quote_params)
    quote_status = current_user.objects.build(quote_params.merge(
                                                object_type: 'Note',
                                                quote_ap_id: quoted_status.ap_id
                                              ))

    # AP IDの設定
    quote_status.ap_id = "#{Rails.application.config.activitypub.base_url}/users/#{current_user.username}/statuses/#{quote_status.id}"

    quote_status
  end

  def create_quote_post_record(quoted_status, quote_status)
    quote_post = QuotePost.new(
      actor: current_user,
      object: quote_status,
      quoted_object: quoted_status,
      shallow_quote: quote_status.content.blank?,
      quote_text: quote_status.content,
      visibility: quote_status.visibility,
      ap_id: "#{quote_status.ap_id}#quote"
    )

    unless quote_post.save
      Rails.logger.error "Failed to create quote post: #{quote_post.errors.full_messages.join(', ')}"
      raise '引用投稿の作成に失敗しました'
    end

    quote_post
  end

  def process_quote_mentions_and_tags(quote_content)
    return if quote_content.blank?

    # メンションの処理
    mentions = extract_mentions(quote_content)
    mentions.each do |mention|
      create_mention_for_quote(mention)
    end

    # ハッシュタグの処理
    hashtags = extract_hashtags(quote_content)
    hashtags.each do |hashtag|
      associate_tag_with_quote(hashtag)
    end
  end

  def create_mention_for_quote(mentioned_actor)
    return if mentioned_actor == current_user

    Mention.find_or_create_by(
      object: @quote_status,
      actor: mentioned_actor
    )
  end

  def associate_tag_with_quote(tag)
    ObjectTag.find_or_create_by(
      object: @quote_status,
      tag: tag
    )
  end
end
