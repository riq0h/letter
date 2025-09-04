# frozen_string_literal: true

class ObjectsController < ApplicationController
  include ActivityPubRequestHandling

  skip_before_action :verify_authenticity_token
  before_action :set_object, only: [:show]
  before_action :ensure_activitypub_request, only: [:show]

  # GET /objects/{id}
  # ActivityPub Object を返す
  def show
    object_data = build_object_data(@object)

    render json: object_data,
           content_type: 'application/activity+json; charset=utf-8'
  end

  private

  def set_object
    # ap_id の末尾部分（nanoid）から Object を検索
    id_param = params[:id]

    # まず直接IDで検索を試行
    @object = ActivityPubObject.find_by(id: id_param) if id_param.match?(/^\d+$/)

    # 見つからない場合は ap_id のパターンで検索
    @object ||= ActivityPubObject.find_by('ap_id LIKE ?', "%/posts/#{id_param}")

    return if @object

    render json: { error: 'Object not found' }, status: :not_found
  end

  def ensure_activitypub_request
    super(status: :moved_permanently)
  end

  def build_object_data(object)
    base_data = build_base_object_data(object)
    base_data.merge(build_extended_object_data(object))
  end

  def build_base_object_data(object)
    base_data = {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => object.ap_id,
      'type' => object.object_type,
      'attributedTo' => object.actor.ap_id,
      'content' => build_activitypub_content(object.content),
      'published' => object.published_at.iso8601,
      'url' => object.public_url
    }

    # 編集済みの場合はupdatedフィールドを追加
    base_data['updated'] = object.edited_at.iso8601 if object.edited?

    base_data
  end

  def build_extended_object_data(object)
    {
      'inReplyTo' => object.in_reply_to_ap_id,
      'to' => build_audience(object, :to),
      'cc' => build_audience(object, :cc),
      'attachment' => build_attachments(object),
      'tag' => ActivityBuilders::TagBuilder.new(object).build,
      'mentions' => build_mentions(object),
      'summary' => object.summary,
      'sensitive' => object.sensitive?,
      'replies' => build_replies_collection(object),
      'source' => build_source_data(object)
    }.compact
  end

  def build_replies_collection(object)
    {
      'type' => 'Collection',
      'totalItems' => object.replies_count
    }
  end

  def build_source_data(object)
    {
      'content' => object.content_plaintext,
      'mediaType' => 'text/plain'
    }
  end

  def build_audience(object, type)
    ActivityBuilders::AudienceBuilder.new(object).build(type)
  end

  def build_attachments(object)
    object.media_attachments.map do |attachment|
      {
        'type' => 'Document',
        'mediaType' => attachment.content_type,
        'url' => build_absolute_media_url(attachment),
        'name' => attachment.description || attachment.file_name,
        'width' => attachment.width,
        'height' => attachment.height,
        'blurhash' => attachment.blurhash
      }.compact
    end
  end

  def build_mentions(object)
    return [] if object.mentions.blank?

    object.mentions.includes(:actor).map do |mention|
      {
        'type' => 'Mention',
        'href' => mention.actor.ap_id,
        'name' => "@#{mention.actor.username}@#{mention.actor.domain}"
      }
    end
  rescue StandardError => e
    Rails.logger.warn "Failed to build mentions for object #{object.id}: #{e.message}"
    []
  end

  def build_activitypub_content(content)
    return content if content.blank?

    # ActivityPub配信用: 絵文字HTMLをショートコードに戻す
    # Mastodonは content でショートコード、tag配列で絵文字メタデータを期待
    content.gsub(/<img[^>]*alt=":([^"]+):"[^>]*\/>/, ':\1:')
  end

  def build_absolute_media_url(attachment)
    # ローカルファイルの場合はurlメソッドを使用
    return attachment.url if attachment.file.attached?

    # リモートURLがある場合は相対URLを絶対URLに変換
    return nil if attachment.remote_url.blank?

    if attachment.remote_url.start_with?('/')
      # .envから設定されたActivityPubドメインを使用
      base_url = Rails.application.config.activitypub.base_url
      "#{base_url}#{attachment.remote_url}"
    else
      attachment.remote_url
    end
  end
end
