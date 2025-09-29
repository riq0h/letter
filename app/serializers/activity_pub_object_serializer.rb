# frozen_string_literal: true

class ActivityPubObjectSerializer
  include TextLinkingHelper

  def initialize(object)
    @object = object
  end

  def to_activitypub
    data = base_activitypub_data.merge(extended_activitypub_data)
    data = clean_null_values(data)

    data = add_poll_data(data) if @object.poll.present?
    add_fep044f_context(data)
  end

  private

  attr_reader :object

  delegate :actor, :poll, to: :object

  def base_activitypub_data
    {
      'id' => object.ap_id,
      'type' => object.object_type,
      'attributedTo' => actor.ap_id,
      'content' => build_activitypub_content,
      'published' => object.published_at.iso8601,
      'url' => object.public_url
    }.tap do |data|
      data['updated'] = object.edited_at.iso8601 if object.edited?
    end
  end

  def extended_activitypub_data
    {
      'inReplyTo' => object.in_reply_to_ap_id,
      'to' => build_audience_list(:to),
      'cc' => build_audience_list(:cc),
      'attachment' => build_attachment_list,
      'tag' => build_tag_list,
      'summary' => object.summary,
      'sensitive' => object.sensitive?,
      'atomUri' => object.ap_id,
      'conversation' => conversation_uri,
      'likes' => likes_collection_data,
      'shares' => shares_collection_data,
      'source' => source_data,
      'replies' => replies_collection_data,
      'interactionPolicy' => build_interaction_policy
    }.tap do |data|
      add_quote_data(data) if object.quoted?
    end
  end

  def clean_null_values(data)
    data['inReplyTo'] = data['inReplyTo'] || nil
    data['summary'] = data['summary'] || nil
    data.reject { |k, v| v.nil? && %w[inReplyTo summary].exclude?(k) }
  end

  def add_poll_data(data)
    data['type'] = 'Question'
    data['endTime'] = poll.expires_at.iso8601 if poll.expires_at
    data['votersCount'] = poll.voters_count || 0

    if poll.multiple
      data['anyOf'] = build_poll_options
    else
      data['oneOf'] = build_poll_options
    end

    data
  end

  def build_poll_options
    return [] unless poll.present? && poll.options.present?

    poll.options.map.with_index do |option, index|
      {
        'type' => 'Note',
        'name' => option['title'],
        'replies' => {
          'type' => 'Collection',
          'totalItems' => poll.option_votes_count(index)
        }
      }
    end
  end

  def build_activitypub_content
    return object.content if object.content.blank?

    auto_link_urls(object.content)
  end

  def build_audience_list(type)
    ActivityBuilders::AudienceBuilder.new(object).build(type)
  end

  def build_attachment_list
    ActivityBuilders::AttachmentBuilder.new(object).build
  end

  def build_tag_list
    ActivityBuilders::TagBuilder.new(object).build
  end

  def source_data
    {
      'content' => object.content_plaintext,
      'mediaType' => 'text/plain'
    }
  end

  def replies_collection_data
    {
      'type' => 'Collection',
      'totalItems' => object.replies_count || 0
    }
  end

  def conversation_uri
    return object.conversation_ap_id if object.conversation_ap_id.present?

    "tag:#{Rails.application.config.activitypub.domain},#{object.published_at.strftime('%Y-%m-%d')}:objectId=#{object.id}:objectType=Conversation"
  end

  def likes_collection_data
    {
      'id' => "#{object.ap_id}/likes",
      'type' => 'Collection',
      'totalItems' => object.favourites_count
    }
  end

  def shares_collection_data
    {
      'id' => "#{object.ap_id}/shares",
      'type' => 'Collection',
      'totalItems' => object.reblogs_count
    }
  end

  def add_quote_data(data)
    quote_post = object.quote_posts.first
    return unless quote_post

    data['quoteUrl'] = quote_post.quoted_object.ap_id
    data['_misskey_quote'] = quote_post.quoted_object.ap_id
    data['quoteUri'] = quote_post.quoted_object.ap_id # Fedibird互換
  end

  def build_interaction_policy
    {
      'canQuote' => {
        'automaticApproval' => ['https://www.w3.org/ns/activitystreams#Public']
      }
    }
  end

  def add_fep044f_context(data)
    # FEP-044f用のJSON-LDコンテキストを追加
    context = [
      'https://www.w3.org/ns/activitystreams',
      {
        'gts' => 'https://gotosocial.org/ns#',
        'interactionPolicy' => {
          '@id' => 'gts:interactionPolicy',
          '@type' => '@id'
        },
        'canQuote' => {
          '@id' => 'gts:canQuote',
          '@type' => '@id'
        },
        'automaticApproval' => {
          '@id' => 'gts:automaticApproval',
          '@type' => '@id'
        }
      }
    ]

    data['@context'] = context
    data
  end
end
