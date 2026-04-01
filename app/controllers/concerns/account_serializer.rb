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

    # アカウント固有のフラグを設定
    result[:suspended] = account.suspended? if account.respond_to?(:suspended?)
    result[:roles] = account.admin? ? [{ id: '1', name: 'Admin', color: '' }] : [] if is_self

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
      display_name: sanitize_plain_text(account.display_name || account.username),
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
    avatar = account.avatar_url || default_avatar_url
    header = account.header_url || default_header_url

    {
      avatar: avatar,
      avatar_static: avatar,
      header: header,
      header_static: header
    }
  end

  def count_attributes(account)
    {
      followers_count: account.followers_count || 0,
      following_count: account.following_count || 0,
      statuses_count: account.posts_count || 0,
      last_status_at: account_last_status_at(account)
    }
  end

  def metadata_attributes
    {
      noindex: false,
      suspended: false,
      moved: nil,
      roles: [],
      emojis: [],
      fields: []
    }
  end

  def account_emojis(account)
    return [] if account.display_name.blank? && account.note.blank? && account.fields.blank?

    text_content = [account.display_name, account.note].compact.join(' ')
    if account.fields.present?
      begin
        fields = JSON.parse(account.fields)
        text_content = "#{text_content} #{fields.map { |f| [f['name'], f['value']].compact.join(' ') }.join(' ')}"
      rescue JSON::ParserError
        # ignore
      end
    end

    emojis = if defined?(@account_emoji_cache) && @account_emoji_cache
               resolve_account_emojis_from_cache(text_content)
             else
               EmojiPresenter.extract_emojis_from(text_content)
             end

    emojis.filter_map(&:to_activitypub)
  rescue StandardError => e
    Rails.logger.warn "Failed to serialize account emojis for actor #{account.id}: #{e.message}"
    []
  end

  def resolve_account_emojis_from_cache(text)
    shortcodes = EmojiPresenter.extract_shortcodes_from(text)
    shortcodes.filter_map do |code|
      @account_emoji_cache[:local][code] ||
        @account_emoji_cache[:remote][code]&.first
    end.uniq(&:shortcode)
  end

  def account_fields(account)
    return [] if account.fields.blank?

    begin
      fields = JSON.parse(account.fields)
      fields.map do |field|
        {
          name: sanitize_field_name(field['name'] || ''),
          value: format_field_value_for_api(field['value'] || ''),
          value_html: format_field_value_for_client(field['value'] || ''),
          verified_at: field['verified_at'] || field['verifiedAt']
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
    return @last_status_at_cache[account.id] if defined?(@last_status_at_cache) && @last_status_at_cache

    latest = account.objects.where(object_type: %w[Note Question]).order(published_at: :desc).pick(:published_at)
    latest&.to_date&.iso8601
  end

  # 複数アカウントのlast_status_atを一括取得
  def preload_last_status_at(actor_ids)
    return if actor_ids.blank?

    results = ActivityPubObject.where(actor_id: actor_ids, object_type: %w[Note Question])
                               .group(:actor_id)
                               .maximum(:published_at)

    new_cache = results.transform_values { |v| v&.to_date&.iso8601 }
    if defined?(@last_status_at_cache) && @last_status_at_cache
      @last_status_at_cache.merge!(new_cache)
    else
      @last_status_at_cache = new_cache
    end
  end

  def self_account_attributes(account)
    {
      source: {
        privacy: 'public',
        sensitive: false,
        language: account_language(account),
        note: account.note || '',
        fields: account_fields(account)
      }
    }
  end

  def account_language(account)
    if account.respond_to?(:language) && account.language.present?
      account.language
    else
      Rails.application.config.activitypub.default_locale
    end
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

    cleaned_value = sanitize_field_html(value)
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

    # まずブロック要素とinvisible spanを除去
    cleaned = sanitize_field_html(value)

    if cleaned.match?(/<a\s+[^>]*href=/i)
      # 既にHTMLリンクが含まれている場合はそのまま返す
      cleaned
    elsif cleaned.match?(/\Ahttps?:\/\//)
      # プレーンURLの場合はリンク化
      domain = begin
        URI.parse(cleaned).host
      rescue StandardError
        cleaned
      end
      %(<a href="#{CGI.escapeHTML(cleaned)}" target="_blank" rel="nofollow noopener noreferrer me">#{CGI.escapeHTML(domain)}</a>)
    else
      # プレーンテキストの場合のみエスケープ
      CGI.escapeHTML(cleaned)
    end
  rescue URI::InvalidURIError
    CGI.escapeHTML(value)
  end

  # フィールド値からブロック要素とinvisible spanを除去し、インライン要素のみ残す
  def sanitize_field_html(value)
    return value unless value.include?('<')

    # invisible spanを除去
    result = value.gsub(/<span class="invisible">[^<]*<\/span>/, '')

    # ellipsis spanの中身だけ残す
    result = result.gsub(/<span class="ellipsis">([^<]*)<\/span>/, '\1')

    # ブロック要素のタグを除去（中身は保持）
    result = result.gsub(/<\/?(?:p|div|section|article|blockquote|pre|ul|ol|li|h[1-6])\b[^>]*>/i, '')

    # 連続する空白・改行を整理
    result.strip.gsub(/\n+/, ' ').gsub(/\s{2,}/, ' ')
  end

  # プレーンテキスト用サニタイズ（display_name、フィールド名など）
  # カスタム絵文字の<img>タグを:shortcode:に変換してからHTMLタグを除去
  def sanitize_plain_text(text)
    return text unless text.include?('<')

    preserved = convert_emoji_html_to_shortcode(text)
    ActionController::Base.helpers.strip_tags(preserved).strip
  end

  alias sanitize_field_name sanitize_plain_text

  # apply_url_links メソッドは TextLinkingHelper から継承
end
