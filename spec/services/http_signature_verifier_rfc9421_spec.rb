# frozen_string_literal: true

require 'rails_helper'

# RFC9421 (HTTP Message Signatures) 受信検証。
# Mastodon 4.7+はRFC9421で先に署名し、401なら旧draftで再送する(double-knocking)
RSpec.describe HttpSignatureVerifier do
  let(:keypair) { OpenSSL::PKey::RSA.new(2048) }
  let(:actor) do
    create(:actor, :remote, ap_id: 'https://remote.example.com/users/signer',
                            public_key: keypair.public_key.to_pem)
  end
  let(:base_url) { Rails.application.config.activitypub.base_url }
  let(:path) { '/users/testuser/inbox' }
  let(:body) { '{"type":"Create","id":"https://remote.example.com/activities/1"}' }

  def content_digest_for(data)
    "sha-256=:#{Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(data))}:"
  end

  # RFC9421署名付きヘッダ一式を構築する
  def rfc9421_headers(created: Time.current.to_i, alg: 'rsa-v1_5-sha256',
                      digest_body: nil, signing_key: keypair)
    components = '("@method" "@target-uri" "content-digest")'
    params_raw = %(#{components};created=#{created};keyid="#{actor.ap_id}#main-key";alg="#{alg}")

    digest = content_digest_for(digest_body || body)
    base = [
      %("@method": POST),
      %("@target-uri": #{base_url}#{path}),
      %("content-digest": #{digest}),
      %("@signature-params": #{params_raw})
    ].join("\n")
    signature = Base64.strict_encode64(signing_key.sign(OpenSSL::Digest.new('SHA256'), base))

    {
      'Signature-Input' => "sig1=#{params_raw}",
      'Signature' => "sig1=:#{signature}:",
      'Content-Digest' => digest
    }
  end

  def verifier_with(headers)
    described_class.new(method: 'POST', path: path, headers: headers, body: body)
  end

  describe 'RFC9421 verification' do
    it 'verifies a valid RFC9421-signed request' do
      expect(verifier_with(rfc9421_headers).verify!(actor.ap_id)).to be true
    end

    it 'rejects when the body does not match Content-Digest' do
      headers = rfc9421_headers(digest_body: 'tampered body')

      expect(verifier_with(headers).verify!(actor.ap_id)).to be false
    end

    it 'rejects a signature made with a different key' do
      other_key = OpenSSL::PKey::RSA.new(2048)
      headers = rfc9421_headers(signing_key: other_key)

      expect(verifier_with(headers).verify!(actor.ap_id)).to be false
    end

    it 'rejects a stale created timestamp' do
      headers = rfc9421_headers(created: 3.hours.ago.to_i)

      expect(verifier_with(headers).verify!(actor.ap_id)).to be false
    end

    it 'rejects unsupported algorithms (sender falls back to draft)' do
      headers = rfc9421_headers(alg: 'rsa-pss-sha512')

      expect(verifier_with(headers).verify!(actor.ap_id)).to be false
    end
  end

  describe 'FEP-521a Multikey鍵での検証' do
    it 'verifies with an actor that only publishes a Multikey (no publicKeyPem)' do
      actor.update_column(:public_key, nil)
      actor_doc = {
        'id' => actor.ap_id,
        'assertionMethod' => [{
          'id' => "#{actor.ap_id}#main-key",
          'type' => 'Multikey',
          'controller' => actor.ap_id,
          'publicKeyMultibase' => MultikeyCodec.encode_rsa(keypair)
        }]
      }
      v = verifier_with(rfc9421_headers)
      allow(v).to receive(:fetch_actor_data).and_return(actor_doc)

      expect(v.verify!(actor.ap_id)).to be true
      # 復元したPEMがactorにキャッシュされる
      expect(actor.reload.public_key).to include('BEGIN PUBLIC KEY')
    end

    it 'verifies an ed25519-signed RFC9421 request with an Ed25519 key' do
      ed = OpenSSL::PKey.generate_key('ED25519')
      actor.update_column(:public_key, ed.public_to_pem)

      components = '("@method" "@target-uri" "content-digest")'
      params_raw = %(#{components};created=#{Time.current.to_i};keyid="#{actor.ap_id}#ed25519-key";alg="ed25519")
      digest = content_digest_for(body)
      base = [
        %("@method": POST),
        %("@target-uri": #{base_url}#{path}),
        %("content-digest": #{digest}),
        %("@signature-params": #{params_raw})
      ].join("\n")
      signature = Base64.strict_encode64(ed.sign(nil, base))
      headers = {
        'Signature-Input' => "sig1=#{params_raw}",
        'Signature' => "sig1=:#{signature}:",
        'Content-Digest' => digest
      }

      expect(verifier_with(headers).verify!(actor.ap_id)).to be true
    end
  end

  describe 'legacy draft signature (非退行)' do
    it 'still verifies draft-cavage signed requests' do
      date = Time.now.utc.httpdate
      digest = "SHA-256=#{Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body))}"
      signing_string = [
        "(request-target): post #{path}",
        'host: test.example.com',
        "date: #{date}",
        "digest: #{digest}"
      ].join("\n")
      signature = Base64.strict_encode64(keypair.sign(OpenSSL::Digest.new('SHA256'), signing_string))
      headers = {
        'Signature' => %(keyId="#{actor.ap_id}#main-key",algorithm="rsa-sha256",) +
                       %(headers="(request-target) host date digest",signature="#{signature}"),
        'Date' => date,
        'Digest' => digest,
        'Host' => 'test.example.com'
      }

      expect(verifier_with(headers).verify!(actor.ap_id)).to be true
    end
  end
end
