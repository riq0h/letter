# frozen_string_literal: true

require 'rails_helper'

# FEP-521a: 自アクターのMultikey(assertionMethod)公開
RSpec.describe ActorSerializer do
  let(:actor) { create(:actor, local: true) }

  it 'publishes the RSA key as a Multikey in assertionMethod (publicKeyと併記)' do
    data = described_class.new(actor).to_activitypub

    method = data['assertionMethod']&.first
    expect(method).to be_present
    expect(method['type']).to eq('Multikey')
    expect(method['id']).to eq(data['publicKey']['id'])
    expect(method['controller']).to eq(data['id'])

    # Multikeyから復元した鍵が既存のPEM鍵と一致する
    decoded = MultikeyCodec.decode(method['publicKeyMultibase'])
    original = OpenSSL::PKey::RSA.new(actor.public_key)
    expect(decoded.n).to eq(original.n)
    expect(decoded.e).to eq(original.e)
  end
end
