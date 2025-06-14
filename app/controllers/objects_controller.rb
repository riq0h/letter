# frozen_string_literal: true

class ObjectsController < ApplicationController
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
    @object ||= ActivityPubObject.find_by('ap_id LIKE ?', "%/posts/#{id_param}") ||
                ActivityPubObject.find_by('ap_id LIKE ?', "%/objects/#{id_param}")

    return if @object

    render json: { error: 'Object not found' }, status: :not_found
  end

  def ensure_activitypub_request
    # ActivityPubリクエストかチェック
    return if activitypub_request?

    # HTML表示にリダイレクト
    redirect_to post_html_path(@object.actor.username, params[:id])
  end

  def activitypub_request?
    return true if request.content_type&.include?('application/activity+json')
    return true if request.content_type&.include?('application/ld+json')

    accept_header = request.headers['Accept'] || ''
    return true if accept_header.include?('application/activity+json')
    return true if accept_header.include?('application/ld+json')

    # デフォルトではActivityPubとして扱う
    true
  end

  def build_object_data(object)
    base_data = build_base_object_data(object)
    base_data.merge(build_extended_object_data(object))
  end

  def build_base_object_data(object)
    {
      '@context' => 'https://www.w3.org/ns/activitystreams',
      'id' => object.ap_id,
      'type' => object.object_type,
      'attributedTo' => object.actor.ap_id,
      'content' => object.content,
      'published' => object.published_at.iso8601,
      'url' => object.public_url
    }
  end

  def build_extended_object_data(object)
    {
      'inReplyTo' => object.in_reply_to_ap_id,
      'to' => build_audience(object, :to),
      'cc' => build_audience(object, :cc),
      'attachment' => build_attachments(object),
      'tag' => build_tags(object),
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
    case object.visibility
    when 'public'
      build_public_audience(type)
    when 'unlisted'
      build_unlisted_audience(object, type)
    when 'followers_only'
      build_followers_audience(object, type)
    when 'direct'
      build_direct_audience(type)
    else
      []
    end
  end

  def build_public_audience(type)
    case type
    when :to
      ['https://www.w3.org/ns/activitystreams#Public']
    when :cc
      [@object.actor.followers_url]
    end
  end

  def build_unlisted_audience(object, type)
    case type
    when :to
      [object.actor.followers_url]
    when :cc
      ['https://www.w3.org/ns/activitystreams#Public']
    end
  end

  def build_followers_audience(object, type)
    case type
    when :to
      [object.actor.followers_url]
    when :cc
      []
    end
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

  def build_absolute_media_url(attachment)
    # 相対URLを絶対URLに変換
    if attachment.remote_url.start_with?('/')
      # .envから設定されたActivityPubドメインを使用
      base_url = Rails.application.config.activitypub.base_url
      "#{base_url}#{attachment.remote_url}"
    else
      attachment.remote_url
    end
  end
end
