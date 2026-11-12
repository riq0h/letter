# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPubHelper, type: :helper do
  describe '#fetch_activitypub_object' do
    let(:uri) { 'https://example.com/users/testuser' }
    let(:mock_client) { instance_double(ActivityPubHttpClient) }
    let(:mock_response) { { 'type' => 'Person', 'id' => uri } }

    before do
      allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return(mock_response)
    end

    it 'delegates to ActivityPubHttpClient.fetch_verified' do
      allow(ActivityPubHttpClient).to receive(:fetch_verified).with(uri)

      helper.fetch_activitypub_object(uri)
      expect(ActivityPubHttpClient).to have_received(:fetch_verified).with(uri)
    end

    it 'returns the response from ActivityPubHttpClient' do
      result = helper.fetch_activitypub_object(uri)

      expect(result).to eq(mock_response)
    end

    context 'with different URI formats' do
      it 'handles actor URIs' do
        actor_uri = 'https://mastodon.social/users/username'
        allow(ActivityPubHttpClient).to receive(:fetch_verified).with(actor_uri)

        helper.fetch_activitypub_object(actor_uri)
        expect(ActivityPubHttpClient).to have_received(:fetch_verified).with(actor_uri)
      end

      it 'handles object URIs' do
        object_uri = 'https://mastodon.social/users/username/statuses/123456'
        allow(ActivityPubHttpClient).to receive(:fetch_verified).with(object_uri)

        helper.fetch_activitypub_object(object_uri)
        expect(ActivityPubHttpClient).to have_received(:fetch_verified).with(object_uri)
      end

      it 'handles activity URIs' do
        activity_uri = 'https://example.com/activities/abc123'
        allow(ActivityPubHttpClient).to receive(:fetch_verified).with(activity_uri)

        helper.fetch_activitypub_object(activity_uri)
        expect(ActivityPubHttpClient).to have_received(:fetch_verified).with(activity_uri)
      end
    end

    context 'when ActivityPubHttpClient raises an error' do
      it 'propagates network errors' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_raise(Timeout::Error)

        expect { helper.fetch_activitypub_object(uri) }.to raise_error(Timeout::Error)
      end

      it 'propagates HTTP errors' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_raise(StandardError, 'HTTP 404')

        expect { helper.fetch_activitypub_object(uri) }.to raise_error(StandardError, 'HTTP 404')
      end
    end

    context 'with nil or empty URI' do
      it 'passes nil URI to client' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).with(nil)

        helper.fetch_activitypub_object(nil)
        expect(ActivityPubHttpClient).to have_received(:fetch_verified).with(nil)
      end

      it 'passes empty string to client' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).with('')

        helper.fetch_activitypub_object('')
        expect(ActivityPubHttpClient).to have_received(:fetch_verified).with('')
      end
    end

    context 'when handling responses' do
      it 'handles Person responses' do
        person_response = {
          'type' => 'Person',
          'id' => 'https://example.com/users/alice',
          'preferredUsername' => 'alice',
          'inbox' => 'https://example.com/users/alice/inbox'
        }
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return(person_response)

        result = helper.fetch_activitypub_object(uri)
        expect(result['type']).to eq('Person')
        expect(result['preferredUsername']).to eq('alice')
      end

      it 'handles Note responses' do
        note_response = {
          'type' => 'Note',
          'id' => 'https://example.com/notes/123',
          'content' => 'Hello, world!',
          'attributedTo' => 'https://example.com/users/alice'
        }
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return(note_response)

        result = helper.fetch_activitypub_object(uri)
        expect(result['type']).to eq('Note')
        expect(result['content']).to eq('Hello, world!')
      end

      it 'handles Activity responses' do
        activity_response = {
          'type' => 'Create',
          'id' => 'https://example.com/activities/456',
          'actor' => 'https://example.com/users/alice',
          'object' => 'https://example.com/notes/123'
        }
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return(activity_response)

        result = helper.fetch_activitypub_object(uri)
        expect(result['type']).to eq('Create')
        expect(result['actor']).to eq('https://example.com/users/alice')
      end

      it 'handles nil responses' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return(nil)

        result = helper.fetch_activitypub_object(uri)
        expect(result).to be_nil
      end

      it 'handles empty hash responses' do
        allow(ActivityPubHttpClient).to receive(:fetch_verified).and_return({})

        result = helper.fetch_activitypub_object(uri)
        expect(result).to eq({})
      end
    end
  end
end
