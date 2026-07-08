# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubHttpClient do
  let(:client) { described_class.new }

  def fake_response(code:, headers: {}, body: '')
    instance_double(HTTParty::Response, code: code, headers: headers,
                                        success?: (200..299).cover?(code), body: body)
  end

  describe '#requires_signature?' do
    it 'treats 401/403 as requiring a signature' do
      expect(client.send(:requires_signature?, fake_response(code: 401))).to be true
      expect(client.send(:requires_signature?, fake_response(code: 403))).to be true
    end

    it 'treats 500 as requiring a signature (Threads returns 500 for unsigned authorized-fetch)' do
      expect(client.send(:requires_signature?, fake_response(code: 500))).to be true
    end

    it 'does not treat 404 as requiring a signature' do
      expect(client.send(:requires_signature?, fake_response(code: 404))).to be false
    end

    it 'does not treat a successful JSON response as requiring a signature' do
      resp = fake_response(code: 200, headers: { 'content-type' => 'application/activity+json' }, body: '{}')
      expect(client.send(:requires_signature?, resp)).to be false
    end
  end

  describe '#handle_signature_requirement' do
    # handle_signature_requirement は Actor.find_by(local: true) を署名用に使う
    before { create(:actor, local: true) }

    it 'learns the domain only when the signed retry succeeds' do
      allow(client).to receive(:fetch_with_signature).and_return({ 'type' => 'Person' })
      expect(client).to receive(:learn_signature_requirement).with('threads.net')

      result = client.send(:handle_signature_requirement,
                           'https://threads.net/ap/users/1/', 'threads.net', fake_response(code: 500), 10)
      expect(result).to eq({ 'type' => 'Person' })
    end

    it 'does not learn when the signed retry also fails (transient 500)' do
      allow(client).to receive(:fetch_with_signature).and_return(nil)
      expect(client).not_to receive(:learn_signature_requirement)

      result = client.send(:handle_signature_requirement,
                           'https://example.com/actor', 'example.com', fake_response(code: 500), 10)
      expect(result).to be_nil
    end
  end
end
