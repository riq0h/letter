# frozen_string_literal: true

# FEP-521a: Multikey形式(publicKeyMultibase)のエンコード/デコード。
# publicKeyMultibase = 'z' + base58btc( multicodecプレフィクス + 鍵バイト列 )
#   - Ed25519公開鍵: multicodec 0xed  (varint: ED 01) + 生の32バイト
#   - RSA公開鍵:     multicodec 0x1205(varint: 85 24) + PKCS#1 DER
module MultikeyCodec
  BASE58_ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
  ED25519_PREFIX = "\xED\x01".b
  RSA_PREFIX = "\x85\x24".b
  # Ed25519公開鍵のSubjectPublicKeyInfo DERヘッダ(この後に生の32バイトが続く)
  ED25519_SPKI_HEADER = ['302a300506032b6570032100'].pack('H*')

  module_function

  # RSA公開鍵(OpenSSL::PKey::RSA)をpublicKeyMultibaseへ
  def encode_rsa(rsa_key)
    pkcs1_der = OpenSSL::ASN1::Sequence([
                                          OpenSSL::ASN1::Integer(rsa_key.n),
                                          OpenSSL::ASN1::Integer(rsa_key.e)
                                        ]).to_der
    "z#{base58_encode(RSA_PREFIX + pkcs1_der)}"
  end

  # publicKeyMultibaseをOpenSSL::PKeyへ(未対応形式はnil)
  def decode(multibase)
    return nil unless multibase.is_a?(String) && multibase.start_with?('z')

    bytes = base58_decode(multibase[1..])
    return nil if bytes.nil?

    if bytes.start_with?(ED25519_PREFIX)
      raw = bytes.byteslice(2..)
      return nil unless raw&.bytesize == 32

      OpenSSL::PKey.read(ED25519_SPKI_HEADER + raw)
    elsif bytes.start_with?(RSA_PREFIX)
      OpenSSL::PKey::RSA.new(bytes.byteslice(2..))
    end
  rescue StandardError
    nil
  end

  def base58_encode(bytes)
    leading_zeros = bytes.each_byte.take_while(&:zero?).size
    num = bytes.unpack1('H*').to_i(16)
    encoded = +''
    while num.positive?
      num, rem = num.divmod(58)
      encoded.prepend(BASE58_ALPHABET[rem])
    end
    ('1' * leading_zeros) + encoded
  end

  def base58_decode(str)
    num = 0
    str.each_char do |c|
      idx = BASE58_ALPHABET.index(c)
      return nil unless idx

      num = (num * 58) + idx
    end
    leading_ones = str.each_char.take_while { |c| c == '1' }.size
    hex = num.zero? ? '' : num.to_s(16)
    hex = "0#{hex}" if hex.length.odd?
    ("\x00" * leading_ones) + [hex].pack('H*')
  end
end
