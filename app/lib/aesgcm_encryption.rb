# frozen_string_literal: true

# aesgcm形式のWebPush暗号化モジュール
# Mastodon互換のlegacy(draft-ietf-webpush-encryption-03)形式で暗号化する
# Moshidon等、aesgcm形式のみ対応するクライアントとの互換性を確保
module AesgcmEncryption
  class Error < StandardError; end

  UNCOMPRESSED_POINT_LENGTH = 65
  AUTH_LENGTH = 16
  SALT_LENGTH = 16

  def self.encrypt(message, p256dh, auth)
    p256dh_raw = Base64.urlsafe_decode64(p256dh)
    auth_raw = Base64.urlsafe_decode64(auth)

    validate_keys!(p256dh_raw, auth_raw)

    # クライアント公開鍵をEC Pointとして復元
    group = OpenSSL::PKey::EC::Group.new('prime256v1')
    client_pub_point = OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(p256dh_raw, 2))

    # エフェメラル鍵ペア生成
    server_key = OpenSSL::PKey::EC.generate('prime256v1')
    server_pub_raw = server_key.public_key.to_bn.to_s(2)

    # ECDH鍵交換
    shared_secret = server_key.dh_compute_key(client_pub_point)

    # salt生成
    salt = OpenSSL::Random.random_bytes(SALT_LENGTH)

    # PRK導出: HKDF-Extract(auth, shared_secret) → HKDF-Expand(prk, "Content-Encoding: auth\0", 32)
    prk = hkdf(auth_raw, shared_secret, "Content-Encoding: auth\0", 32)

    # context構築 (aesgcm形式)
    context = build_context(p256dh_raw, server_pub_raw)

    # content encryption key: HKDF(salt, prk, "Content-Encoding: aesgcm\0P-256" + context, 16)
    content_encryption_key = hkdf(salt, prk, "Content-Encoding: aesgcm\0P-256#{context}", 16)

    # nonce: HKDF(salt, prk, "Content-Encoding: nonce\0P-256" + context, 12)
    nonce = hkdf(salt, prk, "Content-Encoding: nonce\0P-256#{context}", 12)

    # AES-128-GCM暗号化 (aesgcm形式: 2バイトパディング + メッセージ)
    cipher = OpenSSL::Cipher.new('aes-128-gcm')
    cipher.encrypt
    cipher.key = content_encryption_key
    cipher.iv = nonce
    ciphertext = cipher.update("\x00\x00#{message}") + cipher.final
    ciphertext += cipher.auth_tag

    {
      ciphertext: ciphertext,
      salt: salt,
      server_public_key: server_pub_raw
    }
  end

  def self.validate_keys!(p256dh_raw, auth_raw)
    unless p256dh_raw.bytesize == UNCOMPRESSED_POINT_LENGTH
      raise ArgumentError, "p256dh key must be #{UNCOMPRESSED_POINT_LENGTH} bytes (got #{p256dh_raw.bytesize})"
    end

    return if auth_raw.bytesize == AUTH_LENGTH

    raise ArgumentError, "auth key must be #{AUTH_LENGTH} bytes (got #{auth_raw.bytesize})"
  end
  private_class_method :validate_keys!

  # HKDF Extract + Expand (RFC 5869)
  def self.hkdf(salt, ikm, info, length)
    # Extract
    prk = OpenSSL::HMAC.digest('SHA256', salt, ikm)

    # Expand
    output = String.new(encoding: 'BINARY')
    counter = 1
    t = String.new(encoding: 'BINARY')

    while output.bytesize < length
      t = OpenSSL::HMAC.digest('SHA256', prk, t + info + [counter].pack('C'))
      output << t
      counter += 1
    end

    output[0, length]
  end
  private_class_method :hkdf

  # aesgcm形式のcontext構築
  # context = "\0" + [client_pub_len].pack('n') + client_pub + [server_pub_len].pack('n') + server_pub
  def self.build_context(client_pub, server_pub)
    "\0" \
      "#{[client_pub.bytesize].pack('n')}#{client_pub}" \
      "#{[server_pub.bytesize].pack('n')}#{server_pub}"
  end
  private_class_method :build_context
end
