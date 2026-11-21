# frozen_string_literal: true

# Webフロントで、引用した投稿の中に引用元の投稿を表示するためのヘルパ
module QuoteCardHelper
  # 引用元はカードで表示するので、本文に添えられた引用元へのリンクだけの表示
  # (Mastodonの「RE: URL」など、quote-inlineクラスの要素)は除く
  def content_without_quote_fallback(post)
    content = post.content.to_s
    return content unless content.include?('quote-inline') && post.quoted?

    fragment = Nokogiri::HTML::DocumentFragment.parse(content)
    fragment.css('.quote-inline').each(&:remove)
    fragment.to_html
  end

  def quoted_post_url(post)
    return post_html_path(post.actor.username, post.id) if post.local?

    safe_external_url(post.public_url.presence || post.ap_id)
  end

  def quoted_actor_url(actor)
    actor.local? ? profile_path(actor.username) : safe_external_url(actor.ap_id)
  end

  def actor_handle(actor)
    actor.domain.present? ? "@#{actor.username}@#{actor.domain}" : "@#{actor.username}"
  end

  # 引用元の作者のサーバに承認を求めて、まだ返事がないか。
  # 承認の仕組みを持つサーバ(投稿に引用の許可設定がある)の投稿のときだけ。持たないサーバ
  # (Misskeyなど)は返事をしないので、承認待ちとは表示しない
  def quote_awaiting_approval?(quote_post)
    return false unless quote_post.actor&.local? && !quote_post.approved?

    quoted = quote_post.quoted_object
    return false if quoted.nil? || quoted.actor&.local?

    data = JSON.parse(quoted.raw_data.to_s)
    data.is_a?(Hash) && data['interactionPolicy'].is_a?(Hash) && data['interactionPolicy'].key?('canQuote')
  rescue JSON::ParserError
    false
  end
end
