# frozen_string_literal: true

module AccountSerializer
  extend ActiveSupport::Concern
  include StatusSerializer
  include TextLinkingHelper

  private

  def serialized_account(account, is_self: false, lightweight: false)
    result = basic_account_attributes(account)
             .merge(image_attributes(account))
             .merge(count_attributes(account))
             .merge(metadata_attributes)

    if lightweight
      # 軽量版：検索専用の簡素化データ
      result[:fields] = []
      result[:emojis] = []
    else
      result[:fields] = account_fields(account)
      result[:emojis] = account_emojis(account)
    end

    result.merge!(self_account_attributes(account)) if is_self
    result
  end

  def basic_account_attributes(account)
    {
      id: account.id.to_s,
      username: account.username,
      acct: account_acct(account),
      display_name: account.display_name || account.username,
      locked: account.manually_approves_followers || false,
      bot: account.actor_type == 'Service',
      discoverable: account.discoverable || false,
      group: false,
      created_at: account.created_at.iso8601,
      note: format_text_for_api(account.note || ''),
      note_html: format_text_for_client(account.note || ''),
      url: account.public_url || account.ap_id || '',
      uri: account.ap_id || ''
    }
  end

  def image_attributes(account)
    {
      avatar: account.avatar_url || default_avatar_url,
      avatar_static: account.avatar_url || default_avatar_url,
      header: account.header_image_url || default_header_url,
      header_static: account.header_image_url || default_header_url
    }
  end

  def count_attributes(account)
    {
      followers_count: account.followers.count,
      following_count: account.followed_actors.count,
      statuses_count: account_statuses_count(account),
      last_status_at: account_last_status_at(account)
    }
  end

  def metadata_attributes
    {
      noindex: false,
      emojis: [],
      fields: []
    }
  end

  def account_emojis(account)
    return [] if account.display_name.blank? && account.note.blank? && account.fields.blank?

    # display_nameとnoteからemoji shortcodeを抽出
    text_content = [account.display_name, account.note].compact.join(' ')

    # fieldsからもemoji shortcodeを抽出
    if account.fields.present?
      begin
        fields = JSON.parse(account.fields)
        field_content = fields.map { |f| [f['name'], f['value']].compact.join(' ') }.join(' ')
        text_content += " #{field_content}"
      rescue JSON::ParserError
        # JSON解析エラーの場合は無視
      end
    end

    # emojis抽出
    emojis = EmojiParser.new(text_content).emojis_used
    emojis.map(&:to_activitypub)
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize account emojis for actor #{account.id}: #{e.message}"
    []
  end

  def account_fields(account)
    return [] if account.fields.blank?

    begin
      fields = JSON.parse(account.fields)
      fields.map do |field|
        {
          name: field['name'] || '',
          value: format_field_value_for_api(field['value'] || ''),
          value_html: format_field_value_for_client(field['value'] || ''),
          verified_at: nil
        }
      end
    rescue JSON::ParserError
      []
    end
  end

  def account_acct(account)
    account.local? ? account.username : account.full_username
  end

  def account_statuses_count(account)
    account.objects.where(object_type: 'Note').count
  end

  def account_last_status_at(account)
    account.objects.where(object_type: 'Note').maximum(:published_at)&.to_date&.iso8601
  end

  def self_account_attributes(account)
    {
      source: {
        privacy: 'public',
        sensitive: false,
        language: 'ja',
        note: account.note || '',
        fields: account_fields(account)
      }
    }
  end

  def default_avatar_url
    '/icon.png'
  end

  def default_header_url
    '/icon.png'
  end

  # クライアント用のテキスト処理（emoji + URLリンク化）
  def format_text_for_client(text)
    return '' if text.blank?

    # 1. emoji解析
    text_with_emoji = parse_content_for_frontend(text)
    # 2. URLリンク化
    auto_link_urls(text_with_emoji)
  end

  def format_field_value_for_client(value)
    return '' if value.blank?

    cleaned_value = value.gsub(/<span class="invisible">[^<]*<\/span>/, '')
    value_with_emoji = parse_content_for_frontend(cleaned_value)
    auto_link_urls(value_with_emoji)
  end

  def format_text_for_api(text)
    return '' if text.blank?

    if text.include?('<') && text.include?('>')
      text
    else
      escaped_text = CGI.escapeHTML(text).gsub("\n", '<br>')
      apply_url_links(escaped_text)
    end
  end

  def format_field_value_for_api(value)
    return '' if value.blank?

    if value.include?('<a href=')
      value.gsub(/<span class="invisible">[^<]*<\/span>/, '')
    elsif value.match?(/\Ahttps?:\/\//)
      domain = begin
        URI.parse(value).host
      rescue StandardError
        value
      end
      %(<a href="#{CGI.escapeHTML(value)}" target="_blank" rel="nofollow noopener noreferrer me">#{CGI.escapeHTML(domain)}</a>)
    else
      escaped_value = CGI.escapeHTML(value)
      apply_url_links(escaped_value)
    end
  rescue URI::InvalidURIError
    CGI.escapeHTML(value)
  end

  # apply_url_links メソッドは TextLinkingHelper から継承
end
