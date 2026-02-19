# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SharedInboxesController, type: :controller do
  describe 'error handling' do
    context 'when SignatureError is raised' do
      before do
        allow(controller).to receive(:verify_content_type).and_return(true)
        allow(controller).to receive(:parse_activity_json) do
          controller.instance_variable_set(:@activity, {
                                             '@context' => 'https://www.w3.org/ns/activitystreams',
                                             'type' => 'Create',
                                             'actor' => 'https://remote.example.com/users/alice'
                                           })
        end
        allow(controller).to receive(:verify_http_signature).and_raise(
          ActivityPub::SignatureError, 'Signature verification failed'
        )
      end

      it 'returns 401 unauthorized' do
        post :create, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body['error']).to eq('Signature verification failed')
      end
    end

    context 'when ValidationError is raised' do
      before do
        allow(controller).to receive(:verify_content_type).and_return(true)
        allow(controller).to receive(:parse_activity_json).and_raise(
          ActivityPub::ValidationError, 'Invalid activity structure'
        )
      end

      it 'returns 422 unprocessable content' do
        post :create, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to eq('Invalid activity structure')
      end
    end
  end
end
