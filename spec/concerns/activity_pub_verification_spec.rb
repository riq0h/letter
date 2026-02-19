# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubVerification, type: :controller do
  # テスト用のダミーコントローラ
  controller(ApplicationController) do
    include ActivityPubVerification # rubocop:disable RSpec/DescribedClass

    def test_action
      head :ok
    end
  end

  before do
    routes.draw { post 'test_action' => 'anonymous#test_action' }
  end

  let(:signature_template) do
    'keyId="%<key_id>s",algorithm="rsa-sha256",headers="(request-target) host date digest",signature="abc123"'
  end

  describe '#verify_signature' do
    let(:actor_uri) { 'https://remote.example.com/users/alice' }
    let(:forwarder_uri) { 'https://forwarder.example.com/users/bob' }
    let(:verifier) { instance_double(HttpSignatureVerifier) }

    before do
      controller.instance_variable_set(:@activity, {
                                         '@context' => 'https://www.w3.org/ns/activitystreams',
                                         'type' => 'Create',
                                         'actor' => actor_uri
                                       })
      controller.instance_variable_set(:@raw_body, '{}')
      allow(controller).to receive_messages(create_signature_verifier: verifier, relay_activity?: false)
    end

    context 'when keyId matches actor (normal activity)' do
      before do
        request.headers['Signature'] = format(signature_template, key_id: "#{actor_uri}#main-key")
        allow(verifier).to receive(:verify!).with(actor_uri).and_return(true)
      end

      it 'performs normal signature verification' do
        controller.send(:verify_signature)
        expect(verifier).to have_received(:verify!).with(actor_uri)
      end
    end

    context 'when keyId differs from actor (forwarded activity) and signature is valid' do
      before do
        request.headers['Signature'] = format(signature_template, key_id: "#{forwarder_uri}#main-key")
        allow(verifier).to receive(:verify!).with(forwarder_uri).and_return(true)
      end

      it 'accepts the forwarded activity' do
        expect { controller.send(:verify_signature) }.not_to raise_error
        expect(verifier).to have_received(:verify!).with(forwarder_uri)
      end
    end

    context 'when keyId differs from actor (forwarded activity) and signature is invalid' do
      before do
        request.headers['Signature'] = format(signature_template, key_id: "#{forwarder_uri}#main-key")
        allow(verifier).to receive(:verify!).with(forwarder_uri).and_return(false)
      end

      it 'raises SignatureError' do
        expect { controller.send(:verify_signature) }.to raise_error(
          ActivityPub::SignatureError, 'Forwarded activity signature verification failed'
        )
      end
    end

    context 'when relay activity' do
      let(:relay_uri) { 'https://relay.example.com/actor' }

      before do
        allow(controller).to receive(:relay_activity?).and_return(true)
        request.headers['Signature'] = format(signature_template, key_id: "#{relay_uri}#main-key")
        allow(verifier).to receive(:verify!).with(relay_uri).and_return(true)
      end

      it 'verifies using relay actor URI' do
        controller.send(:verify_signature)
        expect(verifier).to have_received(:verify!).with(relay_uri)
      end
    end
  end
end
