# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MultikeyCodec do
  describe 'RSA round-trip' do
    it 'encodes an RSA public key and decodes back to an equivalent key' do
      key = OpenSSL::PKey::RSA.new(2048)
      multibase = described_class.encode_rsa(key)

      expect(multibase).to start_with('z')
      decoded = described_class.decode(multibase)
      expect(decoded).to be_a(OpenSSL::PKey::RSA)
      expect(decoded.n).to eq(key.n)
      expect(decoded.e).to eq(key.e)
    end
  end

  describe 'Ed25519 decode' do
    it 'decodes an Ed25519 Multikey into a key that verifies signatures' do
      ed = OpenSSL::PKey.generate_key('ED25519')
      raw_public = ed.public_to_der[-32..]
      multibase = "z#{described_class.base58_encode(described_class::ED25519_PREFIX + raw_public)}"

      decoded = described_class.decode(multibase)
      signature = ed.sign(nil, 'test message')
      expect(decoded.verify(nil, signature, 'test message')).to be true
    end
  end

  describe 'invalid input' do
    it 'returns nil for non-multibase strings and unknown prefixes' do
      expect(described_class.decode('not-multibase')).to be_nil
      expect(described_class.decode('z1111')).to be_nil
      expect(described_class.decode(nil)).to be_nil
    end
  end

  describe 'base58' do
    it 'round-trips bytes including leading zeros' do
      bytes = "\x00\x00\x01\x02\xFF".b
      encoded = described_class.base58_encode(bytes)
      expect(described_class.base58_decode(encoded)).to eq(bytes)
    end
  end
end
