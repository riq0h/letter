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
      header: account.header_url || default_header_url,
      header_static: account.header_url || default_header_url
    }
  end

  def count_attributes(account)
    {
      followers_count: account.followers_count || 0,
      following_count: account.following_count || 0,
      statuses_count: account.posts_count || 0,
      last_status_at: nil # N+1回避のため一時的に無効化
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
    emojis = EmojiPresenter.extract_emojis_from(text_content)
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
    account.statuses_count || 0
  end

  def account_last_status_at(account)
    account.last_posted_at&.to_date&.iso8601
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

    # 絵文字処理とURLリンク化を一括実行（二重処理を防止）
    parse_content_for_frontend(text)
  end

  def format_field_value_for_client(value)
    return '' if value.blank?

    cleaned_value = value.gsub(/<span class="invisible">[^<]*<\/span>/, '')
    # 絵文字処理とURLリンク化を一括実行（二重処理を防止）
    parse_content_for_frontend(cleaned_value)
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

    if value.include?('<a href=') || value.include?('<a href=\"') || value.match?(/<a\s+[^>]*href=/i)
      # 既にHTMLリンクの場合は invisible span のみ除去して、他の処理はしない
      value.gsub(/<span class="invisible">[^<]*<\/span>/, '')
    elsif value.match?(/\Ahttps?:\/\//)
      # プレーンURLの場合はリンク化
      domain = begin
        URI.parse(value).host
      rescue StandardError
        value
      end
      %(<a href="#{CGI.escapeHTML(value)}" target="_blank" rel="nofollow noopener noreferrer me">#{CGI.escapeHTML(domain)}</a>)
    else
      # プレーンテキストの場合のみエスケープ
      CGI.escapeHTML(value)
    end
  rescue URI::InvalidURIError
    CGI.escapeHTML(value)
  end

  # apply_url_links メソッドは TextLinkingHelper から継承
end
