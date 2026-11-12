# frozen_string_literal: true

require 'rails_helper'

# 署名の有効期間: Mastodonと同じ規則を、取りこぼし防止のためやや寛容な数値で
# (作成+10分が期限、前後2時間の時計ずれを許容、上限24時間。Mastodonは5分/1時間/12時間)
RSpec.describe HttpSignatureVerifier do
  let(:keypair) { OpenSSL::PKey::RSA.new(2048) }
  let(:actor) do
    create(:actor, :remote, ap_id: 'https://remote.example.com/users/signer', public_key: keypair.public_key.to_pem)
  end
  let(:path) { '/users/testuser/inbox' }
  let(:body) { '{"type":"Create","id":"https://remote.example.com/activities/1"}' }
  let(:digest) { "SHA-256=#{Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(body))}" }

  def draft_headers(date:)
    signing_string = ["(request-target): post #{path}", 'host: test.example.com', "date: #{date}", "digest: #{digest}"].join("\n")
    signature = Base64.strict_encode64(keypair.sign(OpenSSL::Digest.new('SHA256'), signing_string))
    {
      'Signature' => %(keyId="#{actor.ap_id}#main-key",algorithm="rsa-sha256",) +
        %(headers="(request-target) host date digest",signature="#{signature}"),
      'Date' => date, 'Digest' => digest, 'Host' => 'test.example.com'
    }
  end

  def verify(headers)
    described_class.new(method: 'POST', path: path, headers: headers, body: body).verify!(actor.ap_id)
  end

  it 'accepts a Date 30 minutes old (sender clock drift)' do
    expect(verify(draft_headers(date: 30.minutes.ago.utc.httpdate))).to be true
  end

  it 'accepts a Date 90 minutes old, which Mastodon would reject' do
    expect(verify(draft_headers(date: 90.minutes.ago.utc.httpdate))).to be true
  end

  it 'accepts a Date 90 minutes in the future' do
    expect(verify(draft_headers(date: 90.minutes.from_now.utc.httpdate))).to be true
  end

  it 'rejects a Date older than the default expiry plus the skew margin' do
    expect(verify(draft_headers(date: 140.minutes.ago.utc.httpdate))).to be false
  end

  it 'rejects a Date more than two hours in the future' do
    expect(verify(draft_headers(date: 130.minutes.from_now.utc.httpdate))).to be false
  end

  it 'logs the reason when rejecting by time' do
    allow(Rails.logger).to receive(:warn)

    verify(draft_headers(date: 3.hours.ago.utc.httpdate))

    expect(Rails.logger).to have_received(:warn).with(/Signature rejected: expired/)
  end

  it 'verifies hs2019 signatures that sign the (created) pseudo-header' do
    created = Time.now.to_i
    signing_string = ["(request-target): post #{path}", "(created): #{created}", "digest: #{digest}"].join("\n")
    signature = Base64.strict_encode64(keypair.sign(OpenSSL::Digest.new('SHA256'), signing_string))
    headers = {
      'Signature' => %(keyId="#{actor.ap_id}#main-key",algorithm="hs2019",created=#{created},) +
                     %(headers="(request-target) (created) digest",signature="#{signature}"),
      'Digest' => digest
    }

    expect(verify(headers)).to be true
  end
end
