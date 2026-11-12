# frozen_string_literal: true

# RFC9421 (HTTP Message Signatures) の受信検証。
# Mastodon 4.7+はRFC9421で署名したリクエストを先に送り、401なら旧draft形式で
# 再送する(double-knocking)。本モジュールが無いと全4.7サーバとの通信が
# 毎回「401→再送」の2往復になる(実測: 旧パーサの拒否1,700件超/ログ窓)。
#
# 対応範囲(Mastodon interopに必要な最小限):
# - アルゴリズム: rsa-v1_5-sha256(alg省略時もRSA扱い) と ed25519(FEP-521a鍵)
# - 導出コンポーネント: @method / @target-uri / @authority / @path / @request-target
# - Content-Digest (RFC9530): sha-256 / sha-512
# - created/expiresの検証(SignatureTimeWindow: Mastodonと同じ規則をやや寛容な数値で)
module Rfc9421SignatureVerification
  # Signature-Inputヘッダを持つリクエストはRFC9421形式
  def rfc9421_request?
    find_header_value('signature-input').present?
  end

  def verify_rfc9421!(actor_uri)
    input = parse_signature_input
    unless input
      Rails.logger.warn "🔐 RFC9421 rejected: unparsable Signature-Input #{find_header_value('signature-input').to_s[0, 200].inspect}"
      return false
    end
    return false unless rfc9421_times_valid?(input)
    return false unless supported_rfc9421_alg?(input)
    return false unless verify_content_digest

    signature = extract_rfc9421_signature(input[:label])
    unless signature
      Rails.logger.warn "🔐 RFC9421 rejected: no signature for label #{input[:label].inspect}"
      return false
    end

    public_key = fetch_actor_public_key(actor_uri)
    return false unless public_key

    base = build_rfc9421_signature_base(input)
    result = verify_signature(signature: signature, signing_string: base, public_key: public_key)

    # 鍵ローテーション対策: 失敗時は鍵を再取得して1回だけ再試行(draft経路と同じ方針)
    if !result && actor_key_needs_refresh?(actor_uri)
      public_key = fetch_actor_public_key(actor_uri, refresh: true)
      result = verify_signature(signature: signature, signing_string: base, public_key: public_key)
    end

    Rails.logger.warn "🔐 RFC9421 signature mismatch (components: #{input[:components].join(' ')})" unless result
    result
  rescue StandardError => e
    Rails.logger.error "RFC9421 signature verification failed: #{e.message}"
    false
  end

  private

  # Signature-Input: sig1=("@method" "@target-uri" ...);created=...;keyid="...";alg="..."
  # params_raw(ラベル以降の全文)は署名ベースの"@signature-params"行で原文のまま使う
  def parse_signature_input
    header = find_header_value('signature-input')
    return nil if header.blank?

    label, params_raw = header.split('=', 2)
    return nil if label.blank? || params_raw.blank?

    components = params_raw[/\A\(([^)]*)\)/, 1].to_s.scan(/"([^"]+)"/).flatten
    return nil if components.empty?

    {
      label: label.strip,
      params_raw: params_raw,
      components: components,
      created: params_raw[/;created=(\d+)/, 1]&.to_i,
      expires: params_raw[/;expires=(\d+)/, 1]&.to_i,
      alg: params_raw[/;alg="([^"]+)"/, 1]
    }
  end

  # Signature: sig1=:Base64:
  def extract_rfc9421_signature(label)
    header = find_header_value('signature')
    return nil if header.blank?

    header[/#{Regexp.escape(label)}=:([A-Za-z0-9+\/=]+):/, 1]
  end

  def rfc9421_times_valid?(input)
    created_at = (Time.at(input[:created]).utc if input[:created])
    expires_at = (Time.at(input[:expires]).utc if input[:expires])
    signature_time_window_valid?(created_at, expires_at)
  end

  def supported_rfc9421_alg?(input)
    alg = input[:alg]
    # ed25519はFEP-521a(Multikey)で配布された鍵で検証する
    return true if alg.blank? || %w[rsa-v1_5-sha256 ed25519].include?(alg)

    Rails.logger.info "🔐 Unsupported RFC9421 algorithm: #{alg} (falling back to 401 → sender retries with draft)"
    false
  end

  # Content-Digest (RFC9530): sha-256=:Base64:, sha-512=:Base64:
  def verify_content_digest
    return true if body.blank?

    header = find_header_value('content-digest')
    unless header
      Rails.logger.warn 'Missing Content-Digest header for RFC9421 request with body'
      return false
    end

    header.scan(/([a-z0-9-]+)=:([A-Za-z0-9+\/=]+):/).any? do |alg, b64|
      digest = case alg
               when 'sha-256' then OpenSSL::Digest::SHA256.digest(body)
               when 'sha-512' then OpenSSL::Digest::SHA512.digest(body)
               end
      digest && ActiveSupport::SecurityUtils.secure_compare(Base64.strict_encode64(digest), b64)
    end
  end

  # RFC9421 §2.5 署名ベース: 各行 `"component": 値`、最終行は"@signature-params"
  def build_rfc9421_signature_base(input)
    lines = input[:components].map { |c| %("#{c}": #{rfc9421_component_value(c)}) }
    lines << %("@signature-params": #{input[:params_raw]})
    lines.join("\n")
  end

  def rfc9421_component_value(component)
    case component
    when '@method' then method
    when '@target-uri' then "#{Rails.application.config.activitypub.base_url}#{path}"
    when '@authority' then Rails.application.config.activitypub.domain
    when '@path' then path.split('?').first
    when '@request-target' then path
    else
      # 通常のHTTPヘッダ(RFC9421の値正規化: 前後trim+内部連続空白の畳み込み)
      find_header_value(component).to_s.strip.gsub(/\s+/, ' ')
    end
  end
end
