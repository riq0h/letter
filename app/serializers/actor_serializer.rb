# frozen_string_literal: true

class ActorSerializer
  include UrlBuildable
  include TextLinkingHelper

  def initialize(actor)
    @actor = actor
  end

  def to_activitypub(request = nil)
    base_activitypub_data(request)
      .merge(activitypub_links(request))
      .merge(activitypub_images(request))
      .merge(activitypub_attachments)
      .merge(activitypub_tags)
      .compact
  end

  private

  attr_reader :actor

  def base_activitypub_data(request = nil)
    base_url = get_base_url(request)
    actor_url = "#{base_url}/users/#{actor.username}"

    {
      '@context' => Rails.application.config.activitypub.context_url + [
        'https://w3id.org/security/v1',
        {
          'schema' => 'http://schema.org#',
          'PropertyValue' => 'schema:PropertyValue',
          'value' => 'schema:value'
        }
      ],
      'type' => actor.actor_type || 'Person',
      'id' => actor_url,
      'preferredUsername' => actor.username,
      'name' => convert_emoji_html_to_shortcode(actor.display_name),
      'summary' => convert_emoji_html_to_shortcode(auto_link_urls(actor.note || '')),
      'url' => actor_url,
      'discoverable' => actor.discoverable,
      'manuallyApprovesFollowers' => actor.manually_approves_followers
    }
  end

  def activitypub_links(request = nil)
    base_url = get_base_url(request)
    actor_url = "#{base_url}/users/#{actor.username}"

    {
      'inbox' => "#{actor_url}/inbox",
      'outbox' => "#{actor_url}/outbox",
      'followers' => "#{actor_url}/followers",
      'following' => "#{actor_url}/following",
      'featured' => "#{actor_url}/collections/featured",
      'endpoints' => {
        'sharedInbox' => "#{base_url}/inbox"
      },
      'publicKey' => {
        'id' => "#{actor_url}#main-key",
        'owner' => actor_url,
        'publicKeyPem' => actor.public_key
      }
    }
  end

  def activitypub_images(_request = nil)
    {
      'icon' => actor.avatar_url ? { 'type' => 'Image', 'url' => actor.avatar_url } : nil,
      'image' => actor.header_url ? { 'type' => 'Image', 'url' => actor.header_url } : nil
    }
  end

  def activitypub_attachments
    return {} if actor.fields.blank?

    begin
      links = JSON.parse(actor.fields)
      attachments = links.filter_map do |link|
        next if link['name'].blank? || link['value'].blank?

        {
          'type' => 'PropertyValue',
          'name' => convert_emoji_html_to_shortcode(link['name']),
          'value' => format_profile_link_value_for_activitypub(link['value'])
        }
      end

      attachments.empty? ? {} : { 'attachment' => attachments }
    rescue JSON::ParserError
      {}
    end
  end

  def activitypub_tags
    emoji_tags = extract_actor_emojis
    emoji_tags.empty? ? {} : { 'tag' => emoji_tags }
  end

  def extract_actor_emojis
    # display_name、note、fieldsからemoji shortcodeを抽出
    text_content = [actor.display_name, actor.note].compact.join(' ')

    # fieldsからもemoji shortcodeを抽出
    if actor.fields.present?
      begin
        fields_data = JSON.parse(actor.fields)
        field_content = fields_data.map { |f| [f['name'], f['value']].compact.join(' ') }.join(' ')
        text_content += " #{field_content}"
      rescue JSON::ParserError
        # JSON解析エラーの場合は無視
      end
    end

    # emojis抽出
    emoji_regex = /:([a-zA-Z0-9_]+):/
    shortcodes = text_content.scan(emoji_regex).flatten.uniq
    return [] if shortcodes.empty?

    # ローカル絵文字のみを対象
    emojis = CustomEmoji.enabled.local.where(shortcode: shortcodes)
    emojis.map(&:to_ap)
  rescue StandardError => e
    Rails.logger.warn "Failed to extract actor emojis for actor #{actor.id}: #{e.message}"
    []
  end

  def format_profile_link_value_for_activitypub(value)
    converted_value = convert_emoji_html_to_shortcode(value)
    return converted_value unless converted_value.match?(/\Ahttps?:\/\//)

    begin
      domain = begin
        URI.parse(converted_value).host
      rescue StandardError
        converted_value
      end
      %(<a href="#{CGI.escapeHTML(converted_value)}" target="_blank" rel="nofollow noopener noreferrer me">#{CGI.escapeHTML(domain)}</a>)
    rescue URI::InvalidURIError
      CGI.escapeHTML(converted_value)
    end
  end

  def convert_emoji_html_to_shortcode(text)
    return text if text.blank?

    # <img ... alt=":shortcode:" ...> を :shortcode: に変換
    text.gsub(/<img[^>]*alt=":([^"]+):"[^>]*\/?>/, ':\1:')
  end

  def get_base_url(_request = nil)
    # 常に設定からのドメインを使用（.envで設定されたACTIVITYPUB_DOMAINを優先）
    build_url_from_config
  end

  def build_url_from_config
    Rails.application.config.activitypub.base_url
  end
end
