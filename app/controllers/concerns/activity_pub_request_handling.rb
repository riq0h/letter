# frozen_string_literal: true

module ActivityPubRequestHandling
  extend ActiveSupport::Concern

  private

  def ensure_activitypub_request(fallback_url: nil, status: :found)
    return if activitypub_request?

    redirect_url = fallback_url || determine_fallback_url
    redirect_to redirect_url, status: status
  end

  # 寛容な判定: 不明な場合はActivityPubとして扱う（リダイレクト判定用）
  def activitypub_request?
    return true if activitypub_content_type?
    return true if activitypub_accept_header?
    return true if activitypub_user_agent?
    return true if activitypub_format?
    return false if html_request?

    # デフォルトではActivityPubとして扱う
    true
  end

  # 厳格な判定: 明示的なAP Content-Type/Acceptヘッダーのみ（ハイブリッドページ用）
  def strict_activitypub_request?
    activitypub_content_type? || activitypub_strict_accept_header?
  end

  def activitypub_content_type?
    content_type = request.content_type
    return false unless content_type

    content_type.include?('application/activity+json') ||
      content_type.include?('application/ld+json')
  end

  def activitypub_accept_header?
    accept_header = request.headers['Accept'] || ''
    accept_header.include?('application/activity+json') ||
      accept_header.include?('application/ld+json') ||
      accept_header.include?('application/json')
  end

  def activitypub_user_agent?
    user_agent = request.headers['User-Agent'] || ''
    # Mastodon や Pleroma などのActivityPubクライアント
    user_agent.match?(/mastodon|pleroma|misskey|gotosocial|pixelfed|lemmy|kbin|activitypub/i)
  end

  def activitypub_strict_accept_header?
    accept_header = request.headers['Accept'] || ''
    accept_header.include?('application/activity+json') ||
      accept_header.include?('application/ld+json')
  end

  def activitypub_format?
    request.format == :json || params[:format] == 'json'
  end

  def html_request?
    request.headers['Accept']&.include?('text/html')
  end

  def determine_fallback_url
    # デフォルトのフォールバック先を決定
    if instance_variable_defined?(:@actor) && @actor
      profile_path(@actor.username)
    elsif instance_variable_defined?(:@object) && @object
      username = @object.actor&.username
      id = @object.id
      post_html_path(username: username, id: id) if username && id
    else
      root_path
    end
  end
end
